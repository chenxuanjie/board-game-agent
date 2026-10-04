import 'dart:async';
import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// Existing native transport supports the app's Windows/system proxy policy.
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import '../../../app/state/app_controller.dart';
import '../models/account_configuration.dart';

final class AccountService extends ChangeNotifier with WidgetsBindingObserver {
  AccountService({
    required AppController controller,
    @visibleForTesting
    Future<IdentityGateway> Function(AccountConfiguration)? gatewayFactory,
    @visibleForTesting Future<void> Function(String?)? switchScope,
  }) : _controller = controller,
       _gatewayFactory = gatewayFactory,
       _switchScope = switchScope;
  static const _configurationKey =
      'board_game_agent.identity.synology.configuration.v2';
  final AppController _controller;
  final Future<IdentityGateway> Function(AccountConfiguration)? _gatewayFactory;
  final Future<void> Function(String?)? _switchScope;
  AccountConfiguration? _configuration;
  IdentityController? _identity;
  IdentityGateway? _gateway;
  bool _observing = false,
      _initializing = false,
      _scopeChanging = false,
      _disposed = false;
  String? _setupError, _scopeError, _appliedScope, _requestedScope;
  int _scopeGeneration = 0;
  Future<void> _scopeQueue = Future.value();
  Timer? _verificationTimer;
  AccountConfiguration? get configuration => _configuration;
  IdentityUser? get user => _identity?.user;
  bool get isConfigured => _configuration != null;
  bool get isSignedIn => user != null;
  bool get isOffline =>
      user != null && _identity?.state.trust == IdentityTrust.cached;
  bool get needsOtp => const {
    IdentityFailureCode.otpRequired,
    IdentityFailureCode.invalidOtp,
  }.contains(_identity?.failure?.code);
  bool get isBusy =>
      _initializing || _scopeChanging || (_identity?.busy ?? false);
  bool get dataScopeReady => !_scopeChanging && _scopeError == null;
  String? get error =>
      _scopeError ?? _setupError ?? _localizedFailure(_identity?.failure);
  String get displayName => user?.displayName ?? user?.email ?? '群晖账号';
  String get nicknameKey => user == null
      ? 'mobile_profile_nickname'
      : 'identity.profile.${_configuration!.accountScope(user!.id)}.nickname';
  Future<void> initialize() async {
    if (_initializing || _disposed) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _initializing = true;
    _setupError = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_configurationKey);
      if (saved != null) {
        _configuration = AccountConfiguration.fromJson(
          jsonDecode(saved) as Map<String, dynamic>,
        );
      }
      if (_gatewayFactory == null) {
        final address = kIsWeb
            ? Uri.base.origin
            : (_configuration?.serviceUrl.origin ??
                  const String.fromEnvironment('IDENTITY_SERVICE_URL'));
        if (address.isNotEmpty) {
          try {
            _configuration = await _discover(Uri.parse(address));
          } catch (_) {
            if (_configuration == null || kIsWeb) rethrow;
          }
        }
      }
      if (_configuration != null) {
        await _disconnect();
        await _connect();
      }
    } catch (_) {
      _setupError = '无法连接登录服务，请稍后重试';
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<AccountConfiguration> _discover(Uri origin) async {
    AccountConfiguration.validateOrigin(origin);
    final client = kIsWeb ? http.Client() : createDefaultAiHttpClient();
    final abort = Completer<void>();
    try {
      final request =
          http.AbortableRequest(
              'GET',
              origin.resolve('/api/identity/configuration'),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..maxRedirects = 0;
      if (!kIsWeb) request.headers['X-Identity-Client'] = 'native-v1';
      final payload = await (() async {
        final response = await client.send(request);
        if (response.statusCode != 200) {
          throw const FormatException('登录服务未就绪');
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (_disposed || bytes.length + chunk.length > 8192) {
            throw const FormatException('登录服务未就绪');
          }
          bytes.addAll(chunk);
        }
        return utf8.decode(bytes);
      })().timeout(const Duration(seconds: 8));
      final next = AccountConfiguration.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      );
      if (next.serviceUrl.origin != origin.origin ||
          (_configuration != null && _configuration!.nasId != next.nasId)) {
        throw const FormatException('登录服务不匹配');
      }
      if (_disposed) {
        throw StateError('Disposed');
      }
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        _configurationKey,
        jsonEncode(next.toJson()),
      )) {
        throw StateError('Configuration persistence failed');
      }
      return next;
    } finally {
      if (!abort.isCompleted) abort.complete();
      client.close();
    }
  }

  Future<void> _connect() async {
    final config = _configuration!;
    IdentityGateway gateway;
    if (_gatewayFactory != null) {
      gateway = await _gatewayFactory(config);
    } else {
      final adapter = SynologyIdentityGateway(
        origin: config.serviceUrl,
        nasId: config.nasId,
        environment: config.environmentId,
        cookieOnly: kIsWeb,
        client: kIsWeb ? null : createDefaultAiHttpClient(),
        storage: kIsWeb
            ? null
            : SecureIdentitySessionStorage(
                appId: 'board_game_agent',
                environment: config.environmentId,
              ),
      );
      await adapter.initialize();
      gateway = adapter;
    }
    if (_disposed) {
      await gateway.dispose();
      return;
    }
    _gateway = gateway;
    _identity = IdentityController(gateway: gateway)
      ..addListener(_identityChanged);
    await _identity!.initialize();
    _identityChanged();
    await _scopeQueue;
    _verificationTimer?.cancel();
    _verificationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_disposed && !isBusy && isSignedIn) unawaited(restore());
    });
  }

  void _identityChanged() {
    if (_disposed) return;
    final target = user == null ? null : _configuration!.accountScope(user!.id);
    if (target != _requestedScope ||
        target != _appliedScope && !_scopeChanging) {
      _requestedScope = target;
      _queueScope(target);
    }
    notifyListeners();
  }

  void _queueScope(String? target) {
    final generation = ++_scopeGeneration;
    _scopeChanging = true;
    _scopeError = null;
    _scopeQueue = _scopeQueue.then((_) async {
      if (_disposed || generation != _scopeGeneration) return;
      try {
        await (_switchScope ?? _controller.switchIdentityScope)(target);
        if (_disposed || generation != _scopeGeneration) return;
        _appliedScope = target;
        _scopeChanging = false;
      } catch (_) {
        if (!_disposed && generation == _scopeGeneration) {
          _scopeError = '账号数据切换未完成，请重试';
        }
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> restore() async {
    if (_initializing || _disposed) return;
    _setupError = null;
    if (_scopeError != null) {
      _queueScope(_requestedScope);
      await _scopeQueue;
      return;
    }
    if (_identity == null) {
      await initialize();
      return;
    }
    await _identity!.restore();
    await _scopeQueue;
  }

  Future<void> signIn({
    required String account,
    required String password,
    String? otp,
  }) async {
    if (isBusy || _disposed || isSignedIn) return;
    if (account.trim().isEmpty || password.isEmpty) {
      _setupError = '请输入账号和密码';
      notifyListeners();
      return;
    }
    if (_identity == null) await restore();
    if (_disposed) return;
    if (_identity == null) {
      _setupError = '登录服务尚未就绪，请稍后重试';
      notifyListeners();
      return;
    }
    _setupError = null;
    await _identity!.signIn(
      account: account.trim(),
      password: password,
      otp: otp,
    );
    await _scopeQueue;
  }

  Future<void> cancelSignIn() async {
    await _identity?.cancelSignIn();
    await _scopeQueue;
  }

  Future<void> signOut() async {
    await _identity?.signOut();
    await _scopeQueue;
  }

  Future<void> saveConfiguration(AccountConfiguration next) async {
    if (isBusy || isSignedIn) throw StateError('请先退出账号');
    _initializing = true;
    notifyListeners();
    try {
      await _disconnect();
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        _configurationKey,
        jsonEncode(next.toJson()),
      )) {
        throw StateError('Configuration persistence failed');
      }
      _configuration = next;
      _setupError = null;
      await _connect();
    } catch (_) {
      _setupError = '登录连接未完成，请重试';
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> clearConfiguration() async {
    if (isBusy || isSignedIn) throw StateError('请先退出账号');
    await _disconnect();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_configurationKey)) {
      throw StateError('Configuration persistence failed');
    }
    _configuration = null;
    _setupError = null;
    notifyListeners();
  }

  Future<void> _disconnect() async {
    _verificationTimer?.cancel();
    _identity?.removeListener(_identityChanged);
    _identity?.dispose();
    _identity = null;
    final gateway = _gateway;
    _gateway = null;
    await gateway?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !isBusy && isConfigured) {
      unawaited(restore());
    }
  }

  static String? _localizedFailure(IdentityFailure? failure) =>
      switch (failure?.code) {
        null => null,
        IdentityFailureCode.network => '无法连接登录服务，请检查网络后重试',
        IdentityFailureCode.timeout => '请求超时，请重试',
        IdentityFailureCode.sessionRejected => '登录已过期，请重新登录',
        IdentityFailureCode.rateLimited => '尝试过于频繁，请稍后重试',
        IdentityFailureCode.providerUnavailable => '群晖登录服务暂不可用，请稍后重试',
        IdentityFailureCode.invalidCredentials => '账号或密码不正确',
        IdentityFailureCode.otpRequired => '请输入双重验证的验证码',
        IdentityFailureCode.invalidOtp => '验证码不正确，请重新输入',
        IdentityFailureCode.accountDenied => '此账号暂不能使用登录服务',
        IdentityFailureCode.passwordChangeRequired => '请先在群晖 DSM 中更新密码，再登录',
        IdentityFailureCode.cancelled => '登录已取消',
        IdentityFailureCode.localCleanupFailed => '退出未完成，请重试后再登录',
        IdentityFailureCode.remoteSignOutUnconfirmed => '已退出本机，请联网确认服务端退出',
        IdentityFailureCode.storage => '无法访问账号安全存储，请重试',
        IdentityFailureCode.unknown => '登录未完成，请重试',
      };
  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disconnect());
    super.dispose();
  }
}
