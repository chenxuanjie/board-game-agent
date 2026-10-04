import 'dart:async';
import 'dart:convert';

import 'package:app_identity/app_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Reuse the application's existing native system/environment proxy transport.
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

  static const _configurationKey = 'board_game_agent.identity.configuration.v1';
  final AppController _controller;
  final Future<IdentityGateway> Function(AccountConfiguration)? _gatewayFactory;
  final Future<void> Function(String?)? _switchScope;
  AccountConfiguration? _configuration;
  IdentityController? _identity;
  Supabase? _supabase;
  WebCookieIdentityGateway? _web;
  http.Client? _transport;
  SecureIdentityLocalStorage? _storage;
  Timer? _callbackTimer;
  bool _observing = false;
  bool _initializing = false;
  bool _scopeChanging = false;
  bool _disposed = false;
  bool _callbackAllowed = false;
  String? _setupError;
  String? _scopeError;
  String? _appliedScope;
  String? _requestedScope;
  int _scopeGeneration = 0;
  Future<void> _scopeQueue = Future.value();
  Future<void> _pendingCleanup = Future.value();
  int _pendingCleanupCount = 0;
  bool _pendingCleanupFailed = false;

  AccountConfiguration? get configuration => _configuration;
  IdentityUser? get user => _identity?.user;
  bool get isConfigured => _configuration != null;
  bool get isSignedIn => user != null;
  bool get isOffline =>
      user != null && _identity?.state.trust == IdentityTrust.cached;
  bool get isAwaitingBrowser =>
      _identity?.phase == IdentityStatus.awaitingCallback ||
      (_callbackAllowed && !(_identity?.busy ?? false));
  bool get isBusy =>
      _initializing ||
      _scopeChanging ||
      _pendingCleanupCount > 0 ||
      _callbackAllowed ||
      (_identity?.busy ?? false);
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
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_configurationKey);
      if (stored != null) {
        _configuration = AccountConfiguration.fromJson(
          jsonDecode(stored) as Map<String, dynamic>,
        );
      } else {
        const url = String.fromEnvironment('IDENTITY_SUPABASE_URL');
        if (url.isNotEmpty) {
          _configuration = AccountConfiguration.fromFields(
            supabaseUrl: url,
            publishableKey: const String.fromEnvironment('IDENTITY_PUBLIC_KEY'),
            providerId: const String.fromEnvironment(
              'IDENTITY_PROVIDER',
              defaultValue: 'custom:synology',
            ),
            webCallback: const String.fromEnvironment('IDENTITY_WEB_CALLBACK'),
          );
        }
      }
      // Browser deployments have an authoritative, same-origin public config.
      if (kIsWeb) await _loadWebConfiguration();
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

  Future<void> _loadWebConfiguration() async {
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.base.resolve('/api/identity/configuration'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic> && body['supabaseUrl'] is String) {
          _configuration = AccountConfiguration.fromJson(body);
        }
      }
    } catch (_) {
      // Local preview and offline mode retain an existing public configuration.
    } finally {
      client.close();
    }
  }

  Future<void> _connect() async {
    final config = _configuration!;
    IdentityGateway gateway;
    if (_gatewayFactory != null) {
      gateway = await _gatewayFactory(config);
    } else if (kIsWeb) {
      final web = WebCookieIdentityGateway(
        origin: Uri.base.origin,
        environment: config.environmentId,
        providerId: config.providerId,
        expectedSupabaseUrl: config.supabaseUrl,
      );
      _web = web;
      await web.initialize();
      gateway = web;
    } else {
      final storage = SecureIdentityLocalStorage(
        appId: 'board_game_agent',
        environment: config.environmentId,
      );
      _storage = storage;
      final prefs = await SharedPreferences.getInstance();
      final pendingAt = prefs.getInt(_pendingLoginKey);
      final age = pendingAt == null
          ? const Duration(days: 1)
          : DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(pendingAt),
            );
      _callbackAllowed =
          age >= Duration.zero &&
          age < const Duration(minutes: 3) &&
          await storage.pkceStorage.getItem(
                key: 'supabase.auth.token-code-verifier',
              ) !=
              null;
      if (_callbackAllowed) {
        _armCallbackTimeout(const Duration(minutes: 3) - age);
      }
      _transport = createDefaultAiHttpClient();
      _supabase = await Supabase.initialize(
        url: config.supabaseUrl.toString(),
        publishableKey: config.publishableKey,
        debug: false,
        httpClient: _transport,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          localStorage: storage,
          pkceAsyncStorage: storage.pkceStorage,
          detectSessionInUriPredicate: (uri) =>
              _callbackAllowed &&
              uri.scheme == config.nativeCallback.scheme &&
              uri.host == config.nativeCallback.host &&
              uri.path == config.nativeCallback.path &&
              !uri.hasFragment &&
              uri.userInfo.isEmpty &&
              (uri.queryParameters.containsKey('code') ||
                  uri.queryParameters.containsKey('error')),
        ),
      );
      gateway = SupabaseIdentityGateway(
        client: _supabase!.client,
        configuration: IdentityConfiguration(
          synologyProviderId: config.providerId,
          webCallback: config.webCallback,
          androidCallback: config.nativeCallback,
          windowsCallback: config.nativeCallback,
        ),
        platform: defaultTargetPlatform == TargetPlatform.windows
            ? IdentityPlatform.windows
            : IdentityPlatform.android,
        clearPersistedSession: storage.clearLocalSession,
      );
    }
    _identity = IdentityController(gateway: gateway);
    _identity!.addListener(_identityChanged);
    await _identity!.initialize();
    _identityChanged();
    await _scopeQueue;
  }

  void _identityChanged() {
    if (_disposed) return;
    final target = user == null ? null : _configuration!.accountScope(user!.id);
    if (target != _requestedScope ||
        target != _appliedScope && !_scopeChanging) {
      _requestedScope = target;
      _queueScope(target);
    }
    if (_callbackAllowed &&
        (_identity?.state.isVerified == true || _identity?.failure != null)) {
      _callbackAllowed = false;
      unawaited(_clearPendingSignIn());
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
        if (_disposed || generation != _scopeGeneration) return;
        _scopeError = '账号数据切换未完成，请重试';
        // Keep private UI covered until a complete account scope is restored.
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> restore() async {
    if (_initializing) return;
    _setupError = null;
    if (_configuration == null && _identity == null) {
      // Deployment owns public configuration. Retry discovery rather than
      // asking users for project keys or authentication endpoints.
      await initialize();
      return;
    }
    if (_scopeError != null) {
      _queueScope(_requestedScope);
      await _scopeQueue;
      return;
    }
    if (_identity == null && _configuration != null) {
      _initializing = true;
      notifyListeners();
      try {
        await _disconnect();
        await _connect();
      } catch (_) {
        _setupError = '无法连接登录服务，请稍后重试';
      } finally {
        _initializing = false;
        if (!_disposed) notifyListeners();
      }
      return;
    }
    await _identity?.restore();
    await _scopeQueue;
  }

  Future<void> signIn() async {
    if (isBusy || _disposed) return;
    await _pendingCleanup;
    if (_pendingCleanupFailed) {
      await _clearPendingSignIn();
      if (_pendingCleanupFailed || _disposed) return;
    }
    if (user != null) {
      _setupError = '请先退出当前账号再重新登录';
      notifyListeners();
      return;
    }
    if (_identity == null) await restore();
    if (_disposed || user != null) return;
    if (_identity == null) {
      _setupError = '登录服务尚未就绪，请稍后重试';
      notifyListeners();
      return;
    }
    _setupError = null;
    if (!kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setInt(
        _pendingLoginKey,
        DateTime.now().millisecondsSinceEpoch,
      )) {
        _setupError = '无法保存登录状态，请重试';
        notifyListeners();
        return;
      }
      _armCallbackTimeout(const Duration(minutes: 3));
    }
    _callbackAllowed = true;
    await _identity!.signIn(IdentityProvider.synology);
    await _scopeQueue;
  }

  void cancelSignIn() {
    _callbackAllowed = false;
    _identity?.cancelSignIn();
    if (_web != null) {
      unawaited(
        _web!.clearLocalSession().catchError((Object _) {
          if (!_disposed) {
            _setupError = '登录状态清理未完成，请重试';
            notifyListeners();
          }
        }),
      );
    }
    unawaited(_clearPendingSignIn());
    notifyListeners();
  }

  Future<void> signOut() async {
    _callbackAllowed = false;
    await _clearPendingSignIn();
    await _identity?.signOut();
    await _scopeQueue;
  }

  Future<void> saveConfiguration(AccountConfiguration next) async {
    if (isBusy || isSignedIn) throw StateError('请先退出账号再修改登录连接');
    _initializing = true;
    notifyListeners();
    try {
      await _disconnect();
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        _configurationKey,
        jsonEncode(next.toJson()),
      )) {
        throw StateError('无法保存登录设置');
      }
      _configuration = next;
      _setupError = null;
      await _connect();
    } catch (_) {
      _setupError = '登录连接未完成，请检查地址、公钥和服务端配置';
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> clearConfiguration() async {
    if (isBusy || isSignedIn) throw StateError('请先退出账号再清除登录连接');
    await _disconnect();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_configurationKey)) {
      throw StateError('无法清除登录设置');
    }
    _configuration = null;
    _setupError = null;
    notifyListeners();
  }

  Future<void> _disconnect() async {
    _callbackTimer?.cancel();
    _callbackAllowed = false;
    _identity?.removeListener(_identityChanged);
    _identity?.dispose();
    _identity = null;
    await _web?.dispose();
    _web = null;
    await _supabase?.dispose();
    _supabase = null;
    _transport?.close();
    _transport = null;
    _storage = null;
  }

  String get _pendingLoginKey =>
      'board_game_agent.identity.${_configuration!.environmentId}.pendingAt';

  void _armCallbackTimeout(Duration remaining) {
    _callbackTimer?.cancel();
    _callbackTimer = Timer(remaining, () {
      if (_disposed) return;
      _callbackAllowed = false;
      _identity?.cancelSignIn();
      _setupError = '登录超时，请重试';
      unawaited(_clearPendingSignIn());
      notifyListeners();
    });
  }

  Future<void> _clearPendingSignIn() {
    _callbackTimer?.cancel();
    if (kIsWeb || _configuration == null) return Future.value();
    final key = _pendingLoginKey;
    final storage = _storage;
    _pendingCleanupCount++;
    final operation = _pendingCleanup.then((_) async {
      var failed = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.remove(key)) failed = true;
      } catch (_) {
        failed = true;
      }
      // Always attempt both stores; either successful removal prevents reuse.
      try {
        await storage?.pkceStorage.removeItem(
          key: 'supabase.auth.token-code-verifier',
        );
      } catch (_) {
        failed = true;
      }
      _pendingCleanupFailed = failed;
      _pendingCleanupCount--;
      if (!_disposed && failed) {
        _setupError = '登录状态清理未完成，请重试';
      }
      if (!_disposed) notifyListeners();
    });
    _pendingCleanup = operation;
    return operation;
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
        IdentityFailureCode.timeout => '登录超时，请重试',
        IdentityFailureCode.sessionRejected => '登录已过期，请重新登录',
        IdentityFailureCode.rateLimited => '操作过于频繁，请稍后重试',
        IdentityFailureCode.providerUnavailable => '群晖登录服务暂不可用，请稍后重试',
        IdentityFailureCode.launchFailed => '无法打开登录页面，请重试',
        IdentityFailureCode.cancelled => '登录已取消',
        IdentityFailureCode.localCleanupFailed => '退出未完成，请重试后再登录',
        IdentityFailureCode.remoteSignOutUnconfirmed =>
          '已退出本机，服务端退出尚未确认，请联网后重试',
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
