import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:app_client/app_client.dart';
import 'package:app_identity/app_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_settings/webdav_settings.dart';
// Use the existing platform proxy policy instead of an ad-hoc HTTP client.
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import '../../../app/state/app_controller.dart';
import '../models/account_configuration.dart';
import '../models/service_configuration.dart';
import '../../community/services/game_comments_service.dart';
import '../../community/services/board_public_sync.dart';
import 'saved_login_store.dart';
import 'service_identity_gateway.dart';
import 'board_personal_store.dart';
import '../../games/services/service_game_statistics.dart';
import '../../games/models/game_vote_record.dart';

/// Owns the sole app-service identity and the account's local workspace.
/// Resource configuration is independent and never supplies login credentials.
final class AccountService extends ChangeNotifier with WidgetsBindingObserver {
  AccountService({
    required AppController controller,
    this.webDav,
    IdentitySessionStorage? savedLoginStorage,
    Future<IdentityGateway> Function(ServiceConfiguration)? gatewayFactory,
    RefreshSessionStore Function(ServiceConfiguration)? sessionStoreFactory,
    http.Client Function()? httpClientFactory,
    PublicSyncFactory? publicSyncFactory,
    Future<void> Function(String?)? switchScope,
    bool? signInSupported,
    bool? browserAccounts,
    Uri? browserOrigin,
  }) : _controller = controller,
       _savedLogins = SavedLoginStore(storage: savedLoginStorage),
       _gatewayFactory = gatewayFactory,
       _storeFactory = sessionStoreFactory,
       _httpClientFactory = httpClientFactory ?? createDefaultAiHttpClient,
       _publicSyncFactory = publicSyncFactory ?? BoardPublicSync.open,
       _switchScope = switchScope,
       _browserOrigin = browserOrigin,
       usesWebAccount = browserAccounts ?? kIsWeb,
       supportsSignIn = signInSupported ?? true {
    _controller.configureAccountReactions(requireAccount: true);
  }

  static const authenticationTimeout = Duration(seconds: 45);
  static const serviceOriginKey = 'board_game_agent.app_service.origin.v1';
  static const _resourceKey = 'board_game_agent.resource_connections.v1';
  final AppController _controller;
  final WebDavSettingsController? webDav;
  final bool usesWebAccount, supportsSignIn;
  final Uri? _browserOrigin;
  final Future<IdentityGateway> Function(ServiceConfiguration)? _gatewayFactory;
  final RefreshSessionStore Function(ServiceConfiguration)? _storeFactory;
  final http.Client Function() _httpClientFactory;
  final PublicSyncFactory _publicSyncFactory;
  final Future<void> Function(String?)? _switchScope;
  final SavedLoginStore _savedLogins;
  ServiceConfiguration? _serviceConfiguration;
  AccountConfiguration? _configuration;
  IdentityGateway? _gateway;
  IdentityController? _identity;
  Timer? _verificationTimer;
  bool _disposed = false,
      _initializing = false,
      _signingIn = false,
      _scopeChanging = false,
      _observing = false;
  String? _setupError, _scopeError, _appliedScope, _requestedScope, _nickname;
  int _scopeGeneration = 0, _loginGeneration = 0;
  Future<void> _scopeQueue = Future.value();
  BoardPersonalStore? _personalStore;
  AppJsonClient? _businessClient;
  GameCommentsService? _comments;
  BoardPublicSync? _publicSync;
  String? _publicSyncError;
  int _publicGeneration = 0;
  final _statisticsReaders = <String, ServiceGameStatistics>{};
  String? get publicSyncError => _publicSyncError ?? _publicSync?.error;
  final _personalWatchers = <StreamSubscription<dynamic>>[];
  Timer? _personalRefresh;
  bool _refreshingPersonal = false;
  String? get personalSyncError => _personalStore?.syncError;

  AppController get controller => _controller;
  AccountConfiguration? get configuration => _configuration;
  ServiceConfiguration? get serviceConfiguration => _serviceConfiguration;
  String get serviceAddress => _serviceConfiguration?.origin.origin ?? '';
  IdentityUser? get user => _identity?.user;
  bool get isConfigured => _serviceConfiguration != null;
  bool get isSignedIn => user != null;
  bool get isOffline =>
      user != null && _identity?.state.trust == IdentityTrust.cached;
  bool get isBusy =>
      _initializing ||
      _signingIn ||
      _scopeChanging ||
      (_identity?.busy ?? false);
  bool get dataScopeReady => !_scopeChanging && _scopeError == null;
  bool get needsOtp => const {
    IdentityFailureCode.otpRequired,
    IdentityFailureCode.invalidOtp,
  }.contains(_identity?.failure?.code);
  String? get error =>
      _scopeError ?? _setupError ?? _localizedFailure(_identity?.failure);
  String get displayName =>
      _nickname?.isNotEmpty == true ? _nickname! : user?.displayName ?? '账号';
  String? get currentAccountScope =>
      user == null ? null : _serviceConfiguration!.accountScope(user!.id);
  String get nicknameKey => user == null
      ? 'mobile_profile_nickname'
      : 'app_service.profile.$currentAccountScope.nickname';

  // These capabilities are not supplied by authentication. Their old NAS
  // transports are never attached to a new service session.
  GameCommentsService? get comments => _comments;

  Future<String> aiAccessToken() async {
    final gateway = _gateway, current = user, generation = _scopeGeneration;
    if (gateway is! ServiceIdentityGateway ||
        current == null ||
        _scopeChanging ||
        _disposed) {
      throw StateError('请先登录后使用 Loomex');
    }
    final token = await gateway.accessToken(current.id);
    if (_disposed ||
        _scopeChanging ||
        generation != _scopeGeneration ||
        user?.id != current.id) {
      throw StateError('账号已切换，请重新发送');
    }
    return token;
  }

  List<SavedLogin> get savedLogins => _savedLogins.entries
      .where((e) => e.environment == _serviceConfiguration?.environmentId)
      .toList(growable: false);
  String? _savedLoginError;
  String? get savedLoginError => _savedLoginError;
  bool _savedLoginNeedsReload = false;
  bool get savedLoginNeedsReload => _savedLoginNeedsReload;
  Future<void> loadSavedLogins() async {
    if (usesWebAccount || _disposed) return;
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
    if (isBusy || _disposed) return;
    try {
      await _savedLogins.forget(entry);
      _savedLoginError = null;
    } catch (_) {
      _savedLoginError = '已保存账号未移除，请重试';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (_initializing || _disposed) return;
    if (_identity != null) {
      if (_serviceConfiguration case final config?) {
        _controller.configureApplicationLibrary(config.origin);
      }
      await restore();
      return;
    }
    _initializing = true;
    if (!_observing && supportsSignIn) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      // Resource configuration cannot prevent independent account recovery.
      try {
        final resources = prefs.getString(_resourceKey);
        _configuration ??= resources == null
            ? AccountConfiguration.fromResources(
                sources: _controller.assetSourceConfigs,
              )
            : AccountConfiguration.fromJson(
                jsonDecode(resources) as Map<String, dynamic>,
              );
      } catch (_) {
        _configuration ??= AccountConfiguration.defaults;
      }
      final address = usesWebAccount
          ? (_browserOrigin ?? Uri.base).origin
          : prefs.getString(serviceOriginKey) ??
                const String.fromEnvironment('APP_SERVICE_ORIGIN');
      if (address.isNotEmpty) {
        _serviceConfiguration = ServiceConfiguration(Uri.parse(address));
        await _connect();
      }
      _setupError = null;
      unawaited(loadSavedLogins());
    } catch (_) {
      _setupError = '账号服务连接未完成，请重试';
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> configureService(String address) async {
    if (usesWebAccount) throw StateError('账号服务由当前站点管理');
    if (isBusy || isSignedIn || _disposed) throw StateError('请先退出账号');
    final next = ServiceConfiguration(Uri.parse(address.trim()));
    _initializing = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(serviceOriginKey, next.origin.origin)) {
        throw StateError('Service configuration could not be saved');
      }
      await _disconnect();
      _serviceConfiguration = next;
      _setupError = null;
      await _connect(restoreSession: false);
    } finally {
      _initializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _connect({bool restoreSession = true}) async {
    final config = _serviceConfiguration!;
    _controller.configureApplicationLibrary(config.origin);
    IdentityGateway gateway;
    if (_gatewayFactory != null) {
      gateway = await _gatewayFactory(config);
    } else {
      final key =
          'board_game_agent.app_service.session.v1.${config.environmentId}';
      final client = AppJsonClient(
        config.origin,
        applicationId: ServiceConfiguration.applicationId,
        client: _httpClientFactory(),
        baseUri: usesWebAccount
            ? config.origin.resolve('/api/')
            : config.origin.resolve('/'),
        requestTimeout: const Duration(seconds: 40),
      );
      final adapter = ServiceIdentityGateway(
        configuration: config,
        client: client,
        browser: usesWebAccount,
        store:
            _storeFactory?.call(config) ??
            (usesWebAccount
                ? BrowserLogoutStore(key)
                : NativeSessionStore(key: key)),
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
      failedSignInCleanupTimeout: const Duration(seconds: 8),
    )..addListener(_identityChanged);
    if (restoreSession) await _identity!.initialize();
    _identityChanged();
    if (_comments == null && _requestedScope == null) _queueScope(null);
    await _scopeQueue;
    _verificationTimer?.cancel();
    _verificationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_disposed && !isBusy && isSignedIn) unawaited(restore());
    });
  }

  void _identityChanged() {
    if (_disposed) return;
    final target = currentAccountScope;
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
    _nickname = null;
    _controller.configureAccountReactions(requireAccount: true);
    final config = _serviceConfiguration;
    final selectedUser = user;
    final gateway = _gateway;
    _scopeQueue = _scopeQueue.catchError((Object _) {}).then((_) async {
      if (_disposed || generation != _scopeGeneration) return;
      BoardPersonalStore? nextStore;
      try {
        final oldStore = _personalStore;
        await _stopPublicSync();
        _statisticsReaders.clear();
        await _comments?.drain();
        _comments?.dispose();
        _comments = null;
        _businessClient?.close();
        _businessClient = null;
        _personalRefresh?.cancel();
        for (final watcher in _personalWatchers) {
          await watcher.cancel();
        }
        _personalWatchers.clear();
        await oldStore?.database.disconnect();
        final client = config == null
            ? null
            : AppJsonClient(
                config.origin,
                applicationId: ServiceConfiguration.applicationId,
                client: _httpClientFactory(),
                baseUri: config.origin.resolve(usesWebAccount ? '/api/' : '/'),
                maxResponseBytes: 4 * 1024 * 1024,
                requestTimeout: const Duration(seconds: 20),
              );
        _businessClient = client;
        Future<String>? access() =>
            gateway is ServiceIdentityGateway && selectedUser != null
            ? gateway.accessToken(selectedUser.id)
            : null;
        if (target != null &&
            gateway is ServiceIdentityGateway &&
            selectedUser != null &&
            client != null) {
          var dataset = gateway.datasetId;
          if (dataset == null) {
            final result = await client.request(
              '/v1/datasets',
              get: true,
              token: await access(),
            );
            dataset =
                ((result['datasets'] as List).single as Map)['id'] as String;
          }
          nextStore = await BoardPersonalStore.open(target, dataset);
        }
        if (_disposed || generation != _scopeGeneration) {
          await nextStore?.close();
          nextStore = null;
          return;
        }
        if (_switchScope != null) {
          await _switchScope(target);
        } else {
          await _controller.switchIdentityScope(
            target,
            personalStore: nextStore,
          );
        }
        _personalStore = nextStore;
        _controller.configureAccountAi(target);
        nextStore = null;
        await oldStore?.close();
        _appliedScope = target;
        if (_disposed || generation != _scopeGeneration) return;
        _scopeChanging = false;
        bool active() =>
            !_disposed &&
            generation == _scopeGeneration &&
            currentAccountScope == target &&
            !_scopeChanging;
        final token =
            target != null &&
                gateway is ServiceIdentityGateway &&
                selectedUser != null
            ? () => gateway.accessToken(selectedUser.id)
            : null;
        if (client != null && config != null) {
          final scope = target ?? 'public-${config.environmentId}';
          _comments = GameCommentsService(
            client: client,
            scope: scope,
            token: token,
            uid: selectedUser == null
                ? ''
                : sha256
                      .convert(
                        utf8.encode(
                          'board_game_agent.public.v1|${selectedUser.id}',
                        ),
                      )
                      .toString(),
            isActive: active,
            displayName: () => displayName,
          );
          for (final namespace in [
            GameVoteBallot.favoritesNamespace,
            GameVoteBallot.campaign,
          ]) {
            _statisticsReaders[namespace] = ServiceGameStatistics(
              client: client,
              scope: scope,
              namespace: namespace,
              token: token,
              store: _personalStore,
              active: active,
              target: () => namespace == GameVoteBallot.favoritesNamespace
                  ? _controller.favoriteStatistics
                  : _controller.gameVotes,
            );
          }
          _controller.configureAccountReactions(
            scope: scope,
            error: () => publicSyncError ?? personalSyncError,
            provider: (namespace) => _statisticsReaders[namespace]!,
          );
        }
        if (client != null) unawaited(_startPublicSync(client, active));
        if (_personalStore case final store?) {
          store.addListener(() {
            if (active() && identical(_personalStore, store)) notifyListeners();
          });
          _nickname = (await store.preferences())['nickname'] as String;
          for (final table in [
            'favorites',
            'recent_games',
            'preferences',
            'conversations',
            'messages',
            'votes',
          ]) {
            _personalWatchers.add(
              store.database
                  .watch('SELECT * FROM $table')
                  .listen(
                    (_) {
                      if (active()) _schedulePersonalRefresh(store, active);
                    },
                    onError: (Object _) {
                      /* SDK keeps the database and pending queue. */
                    },
                  ),
            );
          }
          // First network synchronization never blocks successful local login.
          unawaited(
            store
                .connect(
                  BoardSyncConnector(
                    client: client!,
                    store: store,
                    token: token!,
                    active: active,
                    userId: selectedUser!.id,
                  ),
                )
                .catchError((Object _) {
                  if (active()) {
                    store.syncError = '个人数据已保存在本机，同步未完成';
                    notifyListeners();
                  }
                }),
          );
        }
      } catch (_) {
        await nextStore?.close();
        if (!_disposed && generation == _scopeGeneration) {
          _scopeError = '账号数据切换未完成，请重试';
        }
      }
      if (!_disposed) notifyListeners();
    });
  }

  void _schedulePersonalRefresh(
    BoardPersonalStore store,
    bool Function() active,
  ) {
    _personalRefresh?.cancel();
    _personalRefresh = Timer(const Duration(milliseconds: 250), () async {
      if (!active() || _refreshingPersonal) return;
      _refreshingPersonal = true;
      try {
        final refreshed = await _controller.reloadServicePersonalState();
        if (active()) {
          _nickname = (await store.preferences())['nickname'] as String;
          notifyListeners();
          if (!refreshed) _schedulePersonalRefresh(store, active);
        }
      } catch (_) {
        if (active()) _schedulePersonalRefresh(store, active);
      } finally {
        _refreshingPersonal = false;
      }
    });
  }

  Future<void> _startPublicSync(
    AppJsonClient client,
    bool Function() active,
  ) async {
    final generation = ++_publicGeneration;
    bool valid() =>
        !_disposed &&
        generation == _publicGeneration &&
        active() &&
        identical(_businessClient, client);
    BoardPublicSync? next;
    try {
      next = await _publicSyncFactory(
        client: client,
        active: valid,
        onStatusChanged: () {
          if (valid()) notifyListeners();
        },
        refresh: (statistics, games) async {
          if (!valid()) throw StateError('Account changed');
          if (statistics) {
            try {
              await Future.wait(
                _statisticsReaders.values.map((reader) => reader.synchronize()),
              );
            } catch (_) {
              if (valid()) {
                _controller.favoriteStatistics.markPublicFailure();
                _controller.gameVotes.markPublicFailure();
              }
              rethrow;
            }
            if (!valid()) throw StateError('Public statistics unavailable');
          }
          final comments = _comments;
          if (comments != null) {
            await comments.initialize();
            if (!valid()) throw StateError('Account changed');
            if (comments.pending || comments.error != null) {
              await comments.synchronize();
            } else if (games.any(comments.watchedGames.contains)) {
              await comments.refreshGames(games);
            }
            if (!valid() || comments.error != null) {
              throw StateError('Comments unavailable');
            }
          }
        },
      );
      if (!valid()) {
        await next.close();
        return;
      }
      _publicSyncError = null;
      _publicSync = next;
      await next.start();
    } catch (_) {
      await next?.close().catchError((Object _) {});
      if (valid()) {
        if (identical(_publicSync, next)) _publicSync = null;
        _publicSyncError = '公共数据实时更新未完成，请重试';
        notifyListeners();
      }
    }
  }

  Future<void> retryPublicSync() async {
    if (_disposed || _scopeChanging) return;
    final sync = _publicSync;
    if (sync != null) {
      try {
        _publicSyncError = null;
        notifyListeners();
        await sync.setForeground(true);
      } catch (_) {
        _publicSyncError = '公共数据实时更新未完成，请重试';
        if (!_disposed) notifyListeners();
      }
    } else if (_businessClient case final client?) {
      final generation = _scopeGeneration;
      await _startPublicSync(
        client,
        () => !_disposed && generation == _scopeGeneration && !_scopeChanging,
      );
    }
  }

  Future<void> restore() async {
    if (_disposed || _initializing || _signingIn) return;
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
    bool savePassword = false,
  }) async {
    if (_disposed || isBusy || isSignedIn || !supportsSignIn) return;
    if (_identity == null) {
      _setupError = '请先配置应用服务地址';
      notifyListeners();
      return;
    }
    if (account.trim().isEmpty || password.isEmpty) {
      _setupError = '请输入账号和密码';
      notifyListeners();
      return;
    }
    final generation = ++_loginGeneration;
    _signingIn = true;
    _setupError = null;
    notifyListeners();
    try {
      await _identity!.signIn(
        account: account.trim(),
        password: password,
        otp: otp,
      );
      await _scopeQueue;
      if (_disposed || generation != _loginGeneration || !isSignedIn) return;
      if (!usesWebAccount) {
        try {
          await _savedLogins.remember(
            environment: _serviceConfiguration!.environmentId,
            username: account,
            password: password,
            savePassword: savePassword,
          );
          _savedLoginError = null;
        } catch (_) {
          _savedLoginError = '已登录，登录信息未保存';
        }
      }
    } finally {
      _signingIn = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> cancelSignIn() async {
    ++_loginGeneration;
    if (isSignedIn) {
      await _identity?.signOut();
    } else {
      await _identity?.cancelSignIn();
    }
    await _scopeQueue;
  }

  Future<void> signOut() async {
    ++_loginGeneration;
    await _identity?.signOut();
    await _scopeQueue;
  }

  Future<void> saveNickname(String nickname) async {
    if (user == null || isBusy || nickname.trim().length > 80) return;
    final key = nicknameKey;
    final store = _personalStore;
    if (store == null) throw StateError('个人数据尚未准备好');
    await store.setPreference('nickname', nickname.trim());
    if (key == nicknameKey) {
      _nickname = nickname.trim();
      notifyListeners();
    }
  }

  // Resource connection editing has no effect on the selected API or identity.
  Future<void> saveConfiguration(AccountConfiguration next) async {
    if (isBusy || _disposed) throw StateError('连接正在处理中');
    if (!await (await SharedPreferences.getInstance()).setString(
      _resourceKey,
      jsonEncode(next.toJson()),
    )) {
      throw StateError('资料连接保存失败');
    }
    _configuration = next;
    notifyListeners();
  }

  Future<void> recoverConnectionConfiguration(AccountConfiguration original) =>
      saveConfiguration(original);
  Future<void> clearConfiguration() async {
    if (isBusy || isSignedIn) throw StateError('请先退出账号');
    await _disconnect();
    if (!await (await SharedPreferences.getInstance()).remove(
      serviceOriginKey,
    )) {
      throw StateError('连接清除失败');
    }
    _serviceConfiguration = null;
    _setupError = null;
    notifyListeners();
  }

  Future<void> _disconnect() async {
    await _stopPublicSync();
    _verificationTimer?.cancel();
    _identity?.removeListener(_identityChanged);
    _identity?.dispose();
    _identity = null;
    final gateway = _gateway;
    _gateway = null;
    await gateway?.dispose();
    _personalRefresh?.cancel();
    for (final watcher in _personalWatchers) {
      await watcher.cancel();
    }
    _personalWatchers.clear();
    await _comments?.drain();
    _comments?.dispose();
    _comments = null;
    _businessClient?.close();
    _businessClient = null;
    await _scopeQueue;
    await _personalStore?.close();
    _personalStore = null;
  }

  Future<void> _stopPublicSync() async {
    ++_publicGeneration;
    final sync = _publicSync;
    _publicSync = null;
    _publicSyncError = null;
    // Invalidated callbacks can no longer write. A failed public database close
    // must not strand identity cleanup or turn login into a public-sync error.
    await sync?.close().catchError((Object _) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final sync = _publicSync;
      if (sync != null) {
        unawaited(sync.setForeground(true).catchError((Object _) {}));
      } else if (_businessClient case final client?
          when !_scopeChanging && !_disposed) {
        final generation = _scopeGeneration;
        unawaited(
          _startPublicSync(
            client,
            () =>
                !_disposed && generation == _scopeGeneration && !_scopeChanging,
          ),
        );
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_publicSync?.setForeground(false).catchError((Object _) {}));
    }
    if (state == AppLifecycleState.resumed && !isBusy && isConfigured) {
      unawaited(restore());
    }
  }

  static String? _localizedFailure(IdentityFailure? failure) =>
      switch (failure?.code) {
        null => null,
        IdentityFailureCode.network => '无法连接账号服务，请检查网络后重试',
        IdentityFailureCode.timeout => '请求超时，请重试',
        IdentityFailureCode.sessionRejected => '登录已过期，请重新登录',
        IdentityFailureCode.rateLimited => '尝试过于频繁，请稍后重试',
        IdentityFailureCode.providerUnavailable => '账号服务暂不可用，请稍后重试',
        IdentityFailureCode.invalidCredentials => '账号或密码不正确',
        IdentityFailureCode.otpRequired => '请输入双重验证的验证码',
        IdentityFailureCode.invalidOtp => '验证码不正确，请重新输入',
        IdentityFailureCode.accountDenied => '此账号暂不能使用登录服务',
        IdentityFailureCode.passwordChangeRequired => '请先在群晖 DSM 中更新密码，再登录',
        IdentityFailureCode.cancelled => null,
        IdentityFailureCode.localCleanupFailed => '退出未完成，请重试后再登录',
        IdentityFailureCode.remoteSignOutUnconfirmed => '已退出本机，请联网确认服务端退出',
        IdentityFailureCode.storage => '无法访问账号安全存储，请重试',
        IdentityFailureCode.unknown => '登录未完成，请重试',
        IdentityFailureCode.unsupportedPlatform => '当前站点账号服务不可用',
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
