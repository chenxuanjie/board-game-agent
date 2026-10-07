import 'dart:async';
import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_settings/webdav_settings.dart';
import 'package:crypto/crypto.dart';
// Existing native transport supports the app's Windows/system proxy policy.
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import '../../../app/state/app_controller.dart';
import '../models/account_configuration.dart';
import '../../settings/services/preferences_service.dart';
import 'account_cloud_sync.dart';
import 'saved_login_store.dart';

final class AccountService extends ChangeNotifier with WidgetsBindingObserver {
  AccountService({
    required AppController controller,
    this.webDav,
    @visibleForTesting IdentitySessionStorage? savedLoginStorage,
    @visibleForTesting IdentitySessionStorage Function(String)? credentialStore,
    @visibleForTesting
    Future<IdentityGateway> Function(AccountConfiguration)? gatewayFactory,
    @visibleForTesting Future<void> Function(String?)? switchScope,
    @visibleForTesting bool? signInSupported,
    @visibleForTesting
    AccountPrivateFiles Function(IdentityGateway)? privateFilesFactory,
  }) : _controller = controller,
       _savedLogins = SavedLoginStore(storage: savedLoginStorage),
       _gatewayFactory = gatewayFactory,
       _switchScope = switchScope,
       _privateFilesFactory = privateFilesFactory,
       _credentialStore = credentialStore,
       supportsSignIn = signInSupported ?? !kIsWeb;
  static const _configurationKey =
      'board_game_agent.identity.synology.direct.configuration.v3';
  static const authenticationTimeout = Duration(seconds: 3);
  final WebDavSettingsController? webDav;
  AppController get controller => _controller;
  final SavedLoginStore _savedLogins;
  String? _savedLoginError;
  String? get savedLoginError => _savedLoginError;
  bool _savedLoginNeedsReload = false;
  bool get savedLoginNeedsReload => _savedLoginNeedsReload;
  List<SavedLogin> get savedLogins => _savedLogins.entries
      .where((e) => e.environment == _configuration?.environmentId)
      .toList(growable: false);

  Future<void> loadSavedLogins() async {
    if (!supportsSignIn || _disposed) return;
    try {
      await _savedLogins.load();
      _savedLoginError = null;
      _savedLoginNeedsReload = false;
    } catch (_) {
      _savedLoginError = '无法读取已保存账号，请重试';
      _savedLoginNeedsReload = true;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> forgetSavedLogin(SavedLogin entry) async {
    if (!supportsSignIn || isBusy || _disposed) return;
    try {
      await _savedLogins.forget(entry);
      _savedLoginError = null;
      _savedLoginNeedsReload = false;
    } catch (_) {
      _savedLoginError = '已保存账号未移除，请重试';
      _savedLoginNeedsReload = false;
    }
    if (!_disposed) notifyListeners();
  }

  final IdentitySessionStorage Function(String)? _credentialStore;
  final Map<String, IdentitySessionStorage> _credentialStores = {};
  Future<void> _resourceQueue = Future.value();
  bool _signingIn = false;
  String? _resourceUserId;
  bool _resourceProjectionReady = false;
  int _loginGeneration = 0;
  IdentitySessionStorage _credentials(String scope) =>
      _credentialStores.putIfAbsent(
        scope,
        () =>
            _credentialStore?.call(scope) ??
            SecureIdentitySessionStorage(
              appId: 'board_game_agent_resources',
              environment: scope,
            ),
      );
  bool get resourceCredentialsReady =>
      isSignedIn &&
      _resourceProjectionReady &&
      _resourceUserId == user?.id &&
      webDav?.saved.username.isNotEmpty == true &&
      webDav?.saved.password.isNotEmpty == true;
  WebDavSettings settingsForResource(Uri target) {
    final config = _configuration;
    if (config == null || !resourceCredentialsReady) {
      return const WebDavSettings();
    }
    for (final server in config.servers) {
      final root = server.webDavRoot(config.storageFolder);
      if (target.origin == root.origin && target.path.startsWith(root.path)) {
        return webDav!.saved.copyWith(baseUrl: root.toString());
      }
    }
    return const WebDavSettings();
  }

  Future<void> _projectResources() {
    if (webDav == null || _configuration == null) return Future.value();
    final work = _resourceQueue.then((_) async {
      if (_disposed) return;
      _resourceProjectionReady = false;
      final config = _configuration!;
      final identity = user;
      final generation = _loginGeneration;
      String username = '', password = '';
      if (identity != null) {
        final raw = await _credentials(config.accountScope(identity.id)).read();
        if (raw != null) {
          final value = jsonDecode(raw) as Map<String, dynamic>;
          if (value['userId'] == identity.id &&
              value['environment'] == config.environmentId) {
            username = value['username'] as String;
            password = value['password'] as String;
          }
        }
      }
      if (_disposed ||
          generation != _loginGeneration ||
          user?.id != identity?.id ||
          !identical(config, _configuration)) {
        return;
      }
      await webDav!.saveConfiguration(
        WebDavSettings(
          mode: ExternalStorageMode.webDav,
          baseUrl: config.activeServer
              .webDavRoot(config.storageFolder)
              .toString(),
          username: username,
          password: password,
        ),
      );
      await _controller.saveAssetSourceConfigs(config.resourceSources);
      if (!_disposed &&
          generation == _loginGeneration &&
          user?.id == identity?.id &&
          identical(config, _configuration)) {
        _resourceUserId = identity?.id;
        _resourceProjectionReady = true;
      }
    });
    _resourceQueue = work.catchError((Object _) {});
    return work;
  }

  Future<void> _persistConfiguration() async {
    if (!await (await SharedPreferences.getInstance()).setString(
      _configurationKey,
      jsonEncode(_configuration!.toJson()),
    )) {
      throw StateError('Configuration persistence failed');
    }
  }

  Future<void> _migrateResourceCredential() async {
    final identity = user;
    final config = _configuration;
    final legacy = webDav?.saved;
    if (identity == null ||
        config == null ||
        legacy == null ||
        legacy.username != identity.displayName ||
        legacy.password.isEmpty ||
        !config.resourceSources.any((s) => s.testUrl == legacy.baseUrl)) {
      return;
    }
    final store = _credentials(config.accountScope(identity.id));
    if (await store.read() != null || _disposed || user?.id != identity.id) {
      return;
    }
    await store.write(
      jsonEncode({
        'version': 1,
        'userId': identity.id,
        'environment': config.environmentId,
        'username': legacy.username,
        'password': legacy.password,
      }),
    );
  }

  final bool supportsSignIn;
  final AppController _controller;
  final Future<IdentityGateway> Function(AccountConfiguration)? _gatewayFactory;
  final Future<void> Function(String?)? _switchScope;
  final AccountPrivateFiles Function(IdentityGateway)? _privateFilesFactory;
  AccountConfiguration? _configuration;
  AccountConfiguration? _pendingLoginConfiguration;
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
  AccountCloudSync? _cloud;
  String? _nickname;
  AccountCloudSync? get cloud => _cloud;
  AccountConfiguration? get configuration => _configuration;
  AccountConfiguration get loginConfiguration =>
      _configuration ??
      AccountConfiguration.fromResources(
        sources: _controller.assetSourceConfigs,
      );
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
      _initializing ||
      _signingIn ||
      _scopeChanging ||
      (_identity?.busy ?? false);
  bool get dataScopeReady => !_scopeChanging && _scopeError == null;
  String? get error =>
      _scopeError ?? _setupError ?? _localizedFailure(_identity?.failure);
  String get displayName => _nickname?.trim().isNotEmpty == true
      ? _nickname!
      : user?.displayName ?? user?.email ?? '群晖账号';
  Future<void> saveNickname(String nickname) async {
    if (user == null || isBusy || nickname.trim().length > 80) return;
    final key = nicknameKey;
    if (!await (await SharedPreferences.getInstance()).setString(
      key,
      nickname.trim(),
    )) {
      throw StateError('昵称保存失败');
    }
    if (user != null && nicknameKey == key) {
      _nickname = nickname.trim();
      notifyListeners();
      await _cloud?.synchronize();
    }
  }

  void _cloudChanged() {
    if (_disposed) return;
    unawaited(_refreshNickname());
    notifyListeners();
  }

  Future<void> _refreshNickname() async {
    final key = nicknameKey;
    String? nickname;
    try {
      nickname = (await SharedPreferences.getInstance()).getString(key);
    } catch (_) {
      return; // A display-name lookup must not block an authenticated account.
    }
    if (!_disposed && key == nicknameKey && _nickname != nickname) {
      _nickname = nickname;
      notifyListeners();
    }
  }

  void _stopCloud() {
    _cloud?.removeListener(_cloudChanged);
    _cloud?.dispose();
    _cloud = null;
    _nickname = null;
  }

  String get nicknameKey => user == null
      ? 'mobile_profile_nickname'
      : 'identity.profile.${_configuration!.accountScope(user!.id)}.nickname';
  Future<void> initialize() async {
    if (_initializing || _disposed) return;
    if (!_observing && supportsSignIn) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _initializing = true;
    unawaited(loadSavedLogins());
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
      if (_configuration == null ||
          (saved != null && jsonDecode(saved)['version'] == 3)) {
        _configuration = AccountConfiguration.fromResources(
          sources: await PreferencesService().loadAssetSourceConfigs(),
          previous: _configuration,
        );
        await _persistConfiguration();
      }
      if (_configuration != null) {
        await _disconnect();
        if (supportsSignIn) await _connect();
        await _migrateResourceCredential();
        await _projectResources();
      }
    } catch (_) {
      _setupError = '无法读取账号配置或安全存储，请重试';
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _connect({bool restoreSession = true}) async {
    final config = _configuration!;
    IdentityGateway gateway;
    if (_gatewayFactory != null) {
      gateway = await _gatewayFactory(config);
    } else {
      final adapter = SynologyIdentityGateway(
        origin: config.nasOrigin,
        identityOrigin: config.identityOrigin,
        environment: config.environmentId,
        client: createDefaultAiHttpClient(),
        storage: SecureIdentitySessionStorage(
          appId: 'board_game_agent',
          environment: config.nasOrigin == config.identityOrigin
              ? config.environmentId
              : '${config.environmentId}_${sha256.convert(utf8.encode(config.nasOrigin.origin)).toString().substring(0, 16)}',
        ),
      );
      try {
        await adapter.initialize();
      } catch (_) {
        await adapter.dispose();
        rethrow;
      }
      gateway = adapter;
    }
    if (_disposed) {
      await gateway.dispose();
      return;
    }
    _gateway = gateway;
    _identity = IdentityController(
      gateway: gateway,
      requestTimeout: authenticationTimeout,
      signInTimeout: authenticationTimeout,
      failedSignInCleanupTimeout: const Duration(milliseconds: 500),
    )..addListener(_identityChanged);
    if (restoreSession) await _identity!.initialize();
    _identityChanged();
    await _scopeQueue;
    _verificationTimer?.cancel();
    _verificationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_disposed && !isBusy && isSignedIn) unawaited(restore());
    });
  }

  void _identityChanged() {
    if (_disposed) return;
    if (_resourceUserId != user?.id) {
      _resourceUserId = null;
      _resourceProjectionReady = false;
    }
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
    _stopCloud();
    _scopeQueue = _scopeQueue.then((_) async {
      if (_disposed || generation != _scopeGeneration) return;
      try {
        await (_switchScope ?? _controller.switchIdentityScope)(target);
        if (_disposed || generation != _scopeGeneration) return;
        _appliedScope = target;
        _scopeChanging = false;
        if (target != null) unawaited(_startCloud(target, generation));
      } catch (_) {
        if (!_disposed && generation == _scopeGeneration) {
          _scopeError = '账号数据切换未完成，请重试';
        }
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _startCloud(String target, int generation) async {
    if (_disposed ||
        generation != _scopeGeneration ||
        user == null ||
        _cloud != null ||
        !dataScopeReady ||
        !(_gateway is SynologyIdentityGateway ||
            _privateFilesFactory != null)) {
      return;
    }
    final identityId = user!.id;
    try {
      final files = _privateFilesFactory != null
          ? _privateFilesFactory(_gateway!)
          : (_gateway as SynologyIdentityGateway).privateFiles(
              appId: 'board_game_agent',
            );
      final cloud = AccountCloudSync(
        controller: _controller,
        scope: target,
        files: files,
        isActive: () =>
            !_disposed &&
            user?.id == identityId &&
            !isOffline &&
            dataScopeReady,
      );
      _cloud = cloud..addListener(_cloudChanged);
      await cloud.initialize().timeout(authenticationTimeout);
      if (!_disposed && generation == _scopeGeneration) {
        await _refreshNickname();
      }
    } catch (_) {
      if (!_disposed &&
          generation == _scopeGeneration &&
          user?.id == identityId) {
        _stopCloud();
        _setupError = '已登录，云同步暂不可用，可重试连接';
      }
    }
    if (!_disposed && generation == _scopeGeneration) notifyListeners();
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
    await _projectResources();
    if (user != null && dataScopeReady && _cloud == null) {
      unawaited(
        _startCloud(_configuration!.accountScope(user!.id), _scopeGeneration),
      );
    }
  }

  Future<void> signIn({
    required String account,
    required String password,
    String? otp,
    String? serverId,
    Uri? customOrigin,
    bool savePassword = false,
  }) async {
    if (!supportsSignIn) {
      _setupError = '网页版暂不支持账号登录，知识库不可用';
      notifyListeners();
      return;
    }
    if (isBusy || _disposed || isSignedIn) return;
    if (account.trim().isEmpty || password.isEmpty) {
      _setupError = '请输入账号和密码';
      notifyListeners();
      return;
    }
    if (_identity == null) await restore();
    if (_disposed || _configuration == null) return;
    final generation = ++_loginGeneration;
    _signingIn = true;
    _setupError = null;
    notifyListeners();
    final original = _configuration!;
    var targetConfig = original;
    NasServerAddress? selected;
    if (!needsOtp) {
      try {
        if (customOrigin != null) {
          SynologyIdentityGateway.validateOrigin(customOrigin);
          final normalized = customOrigin.replace(path: '');
          selected = original.servers
              .where((s) => s.loginOrigin == normalized)
              .firstOrNull;
          if (selected == null) {
            selected = NasServerAddress(
              id: 'custom-login',
              name: '自定义入口',
              address: Uri(scheme: 'https', host: normalized.host).origin,
              loginPort: normalized.port,
              webDavPort: original.activeServer.webDavPort,
            );
            // An unknown host is a separate NAS until explicitly configured:
            // never forward its credentials to the previous device's entrances.
            targetConfig = AccountConfiguration(
              nasOrigin: normalized,
              servers: [selected],
              storageFolder: original.storageFolder,
              activeServerId: selected.id,
            );
            _pendingLoginConfiguration ??= original;
          }
        } else if (serverId != null) {
          selected = original.servers.firstWhere((s) => s.id == serverId);
        }
      } catch (_) {
        _setupError = '请选择有效的群晖 HTTPS 登录地址';
        _signingIn = false;
        notifyListeners();
        return;
      }
    }
    // OTP retries stay on the NAS that issued the challenge.
    final addresses = needsOtp
        ? [original.activeServer]
        : selected != null
        ? [selected]
        : original.servers;
    try {
      for (final server in addresses) {
        if (_disposed || generation != _loginGeneration) return;
        if (_gateway == null ||
            _configuration!.nasOrigin != server.loginOrigin) {
          await _disconnect();
          _configuration = targetConfig.withServer(server.id);
          await _connect(restoreSession: false);
        }
        if (_disposed || generation != _loginGeneration) return;
        if (_gateway?.cachedUser != null) await _identity!.signOut();
        if (_disposed || generation != _loginGeneration) return;
        await _identity!.signIn(
          account: account.trim(),
          password: password,
          otp: otp,
        );
        await _scopeQueue;
        if (_disposed || generation != _loginGeneration) return;
        if (isSignedIn) {
          await _persistConfiguration();
          _pendingLoginConfiguration = null;
          try {
            await _savedLogins.remember(
              environment: _configuration!.environmentId,
              username: account,
              password: password,
              savePassword: savePassword,
              serverId: _configuration!.activeServer.id,
            );
            _savedLoginError = null;
            _savedLoginNeedsReload = false;
          } catch (_) {
            _savedLoginError = '已登录，登录信息未保存，请重新登录后重试';
            _savedLoginNeedsReload = false;
          }
          if (_disposed || generation != _loginGeneration) return;
          if (webDav != null) {
            var credentialSaved = false;
            try {
              await _credentials(_configuration!.accountScope(user!.id)).write(
                jsonEncode({
                  'version': 1,
                  'userId': user!.id,
                  'environment': _configuration!.environmentId,
                  'username': account.trim(),
                  'password': password,
                }),
              );
              credentialSaved = true;
              if (_disposed || generation != _loginGeneration) return;
              await _projectResources();
            } catch (_) {
              _setupError = credentialSaved
                  ? '已登录，资料连接未完成，可重试连接'
                  : '已登录，资料凭据保存失败，可重新登录再试';
            }
          }
          return;
        }
        if (!const {
          IdentityFailureCode.network,
          IdentityFailureCode.timeout,
          IdentityFailureCode.providerUnavailable,
        }.contains(_identity?.failure?.code)) {
          break;
        }
      }
    } catch (_) {
      _setupError = '账号或资料连接未完成，请重试';
      if (isSignedIn) await _identity?.signOut();
      if (_identity != null) await _scopeQueue;
      if (identical(targetConfig, original)) await _projectResources();
    } finally {
      if (!_disposed &&
          !isSignedIn &&
          !needsOtp &&
          !identical(targetConfig, original)) {
        final failure = _setupError ?? _localizedFailure(_identity?.failure);
        try {
          await _disconnect();
          _configuration = original;
          await _connect(restoreSession: false);
          await _projectResources();
        } catch (_) {
          _setupError = '登录连接未完成，请重试';
        }
        _setupError = failure ?? _setupError;
        _pendingLoginConfiguration = null;
      }
      _signingIn = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> cancelSignIn() async {
    ++_loginGeneration;
    if (isSignedIn) {
      await signOut();
      return;
    }
    await _identity?.cancelSignIn();
    await _scopeQueue;
    if (needsOtp || _pendingLoginConfiguration != null) {
      final previous = _pendingLoginConfiguration ?? _configuration!;
      await _disconnect();
      _configuration = previous;
      _pendingLoginConfiguration = null;
      await _connect(restoreSession: false);
      _setupError = null;
    }
    await _projectResources();
  }

  Future<void> signOut() async {
    ++_loginGeneration;
    _resourceProjectionReady = false;
    notifyListeners();
    final scope = user == null ? null : _configuration!.accountScope(user!.id);
    if (scope != null && webDav != null) await _credentials(scope).delete();
    await _identity?.signOut();
    await _scopeQueue;
    await _projectResources();
  }

  Future<void> saveConfiguration(AccountConfiguration next) async {
    if (isBusy) throw StateError('连接正在处理中');
    final current = _configuration;
    final keepsIdentity =
        current != null &&
        next.identityOrigin == current.identityOrigin &&
        next.servers.length == current.servers.length &&
        next.servers.every(
          (s) => current.servers.any(
            (old) => old.id == s.id && old.loginOrigin == s.loginOrigin,
          ),
        );
    if (isSignedIn && !keepsIdentity) throw StateError('修改登录地址前请先退出账号');
    _initializing = true;
    notifyListeners();
    try {
      if (!isSignedIn) await _disconnect();
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        _configurationKey,
        jsonEncode(next.toJson()),
      )) {
        throw StateError('Configuration persistence failed');
      }
      _configuration = next;
      _resourceProjectionReady = false;
      _setupError = null;
      if (_identity == null && supportsSignIn) await _connect();
      await _projectResources();
    } catch (_) {
      _setupError = '登录连接未完成，请重试';
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Recovery runs before app initialization; do not restore an identity or switch
  /// personal data scopes until the normal startup order has completed.
  Future<void> recoverConnectionConfiguration(
    AccountConfiguration original,
  ) async {
    if (_configuration != null) {
      await saveConfiguration(original);
      return;
    }
    if (isBusy || _disposed) throw StateError('Configuration is busy');
    _configuration = original;
    await _persistConfiguration();
  }

  Future<void> clearConfiguration() async {
    if (isBusy || isSignedIn) throw StateError('请先退出账号');
    await _disconnect();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_configurationKey)) {
      throw StateError('Configuration persistence failed');
    }
    _configuration = null;
    _resourceUserId = null;
    _resourceProjectionReady = false;
    if (webDav != null) {
      await webDav!.saveConfiguration(const WebDavSettings());
    }
    _setupError = null;
    notifyListeners();
  }

  Future<void> _disconnect() async {
    _stopCloud();
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
        IdentityFailureCode.network => '无法连接群晖，请检查网络后重试',
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
        IdentityFailureCode.unsupportedPlatform => '网页版暂不支持账号登录，知识库不可用',
      };
  @override
  void dispose() {
    ++_loginGeneration;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disconnect());
    super.dispose();
  }
}
