import 'dart:async';
import 'dart:convert';
import 'package:app_client/app_client.dart';
import 'package:app_identity/app_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/service_configuration.dart';

/// Browser storage contains a logout marker only, never session credentials.
final class BrowserLogoutStore implements RefreshSessionStore {
  BrowserLogoutStore(this.key);
  final String key;
  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  @override
  Future<void> write(String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw const IdentityFailure(IdentityFailureCode.storage);
    }
  }

  @override
  Future<void> delete() async {
    if (!await (await SharedPreferences.getInstance()).remove(key)) {
      throw const IdentityFailure(IdentityFailureCode.storage);
    }
  }
}

/// The app-service protocol is the only authentication provider. No DSM SID,
/// NAS password, old cookie or old vault is inspected or converted here.
final class ServiceIdentityGateway
    implements
        IdentityGateway,
        IdentityVerifiedSignInGateway,
        IdentityLocalSessionCleanup {
  ServiceIdentityGateway({
    required this.configuration,
    required AppJsonClient client,
    required this.store,
    required this.browser,
  }) : session = ServiceSession(client, browser: browser) {
    if (client.applicationId != ServiceConfiguration.applicationId ||
        client.origin.origin != configuration.origin.origin) {
      throw ArgumentError('Scoped application client required');
    }
  }
  final ServiceConfiguration configuration;
  final RefreshSessionStore store;
  final bool browser;
  final ServiceSession session;
  final _events = StreamController<IdentityEvent>.broadcast();
  IdentityUser? _user;
  String? _refresh;
  bool _pendingLogout = false, _disposed = false, _loaded = false;
  bool _authenticating = false, _cancelSaveFailed = false;
  Future<void>? _cancelSave;
  int _generation = 0;
  Future<void> _writes = Future.value();
  Future<IdentityUser?>? _verification;

  @override
  IdentityUser? get cachedUser => _user;
  @override
  Stream<IdentityEvent> get changes => _events.stream;

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw const IdentityFailure(IdentityFailureCode.cancelled);
    }
  }

  Future<void> _persist(String? value) {
    final work = _writes.then(
      (_) => value == null ? store.delete() : store.write(value),
    );
    _writes = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return work.timeout(const Duration(seconds: 10)).catchError((Object _) {
      throw const IdentityFailure(IdentityFailureCode.storage);
    });
  }

  String _record({required bool logout}) => jsonEncode({
    'version': 1,
    'app_id': ServiceConfiguration.applicationId,
    'origin': configuration.origin.origin,
    'logout_pending': logout,
    if (!browser) ...{
      'refresh_token': _refresh,
      if (_user != null) 'user_id': _user!.id,
      if (_user != null) 'display_name': _user!.displayName,
    },
  });

  Future<void> initialize() async {
    if (_loaded) return;
    final generation = _generation;
    try {
      final raw = await store.read().timeout(const Duration(seconds: 10));
      _check(generation);
      if (raw != null) {
        if (raw.length > 32768) throw const FormatException();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['version'] != 1 ||
            data['app_id'] != ServiceConfiguration.applicationId ||
            data['origin'] != configuration.origin.origin) {
          throw const FormatException();
        }
        _pendingLogout = data['logout_pending'] == true;
        if (!browser) {
          final refresh = data['refresh_token'];
          if (refresh != null && (refresh is! String || refresh.isEmpty)) {
            throw const FormatException();
          }
          if (!_pendingLogout && refresh == null) throw const FormatException();
          _refresh = refresh as String?;
          if (!_pendingLogout) _user = _identity(data);
        }
      }
      _loaded = true;
    } on IdentityFailure {
      rethrow;
    } catch (_) {
      throw const IdentityFailure(IdentityFailureCode.storage);
    }
  }

  IdentityUser _identity(Map<String, dynamic> result) {
    final id = result['user_id'];
    final name = result['display_name'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        name != null && (name is! String || name.length > 200)) {
      throw const IdentityFailure(IdentityFailureCode.sessionRejected);
    }
    return IdentityUser(id: id, displayName: name as String?);
  }

  void _validate(Map<String, dynamic> data, {String? expected}) {
    final identity = _identity(data);
    if (data['app_id'] != ServiceConfiguration.applicationId ||
        data['access_token'] is! String ||
        (data['access_token'] as String).isEmpty ||
        expected != null && identity.id != expected) {
      throw const IdentityFailure(IdentityFailureCode.sessionRejected);
    }
  }

  @override
  Future<IdentityUser> signIn({
    required String account,
    required String password,
    String? otp,
  }) async {
    await initialize();
    if (_user != null) await signOut();
    if (_pendingLogout) await _finishLogout();
    final generation = _generation;
    _authenticating = true;
    try {
      final data = await session.login(account, password, otp ?? '');
      _check(generation);
      _validate(data);
      if (!browser) {
        final refresh = data['refresh_token'];
        if (refresh is! String || refresh.isEmpty) {
          throw const IdentityFailure(IdentityFailureCode.sessionRejected);
        }
        _refresh = refresh;
      }
      _user = _identity(data);
      // Persist before publishing success; cancellation queues a tombstone after
      // this write, so a late secure-store completion cannot revive the session.
      await _persist(browser ? null : _record(logout: false));
      _check(generation);
      _events.add(IdentityEvent(type: IdentityEventType.signedIn, user: _user));
      return _user!;
    } catch (error) {
      if (generation == _generation && (_user != null || _refresh != null)) {
        try {
          await signOut();
        } catch (_) {
          /* Tombstone remains retryable. */
        }
      }
      throw _failure(error);
    } finally {
      _authenticating = false;
    }
  }

  @override
  Future<IdentityUser?> verifyCurrentUser() =>
      _verification ??= _verify().whenComplete(() => _verification = null);

  Future<IdentityUser?> _verify() async {
    await initialize();
    if (_pendingLogout) {
      await _finishLogout();
      return null;
    }
    if (!browser && _refresh == null) return null;
    final generation = _generation;
    final expected = _user?.id;
    try {
      final data = await session.refresh(_refresh);
      _check(generation);
      _validate(data, expected: expected);
      final identity = _identity(data);
      _user = IdentityUser(
        id: identity.id,
        displayName: identity.displayName ?? _user?.displayName,
      );
      _events.add(
        IdentityEvent(type: IdentityEventType.tokenRefreshed, user: _user),
      );
      return _user;
    } catch (error) {
      final failure = _failure(error);
      if (generation == _generation &&
          failure.code == IdentityFailureCode.sessionRejected) {
        _user = null;
        _refresh = null;
        await _persist(null);
      }
      throw failure;
    }
  }

  @override
  void cancelRequests() {
    _generation++;
    session.client.cancelRequests();
    if (_authenticating) {
      _pendingLogout = true;
      final tombstone = _record(logout: true);
      _user = null;
      _cancelSave = _persist(tombstone).catchError((Object _) {
        _cancelSaveFailed = true;
      });
    }
  }

  @override
  Future<void> clearLocalSession() async {
    cancelRequests();
    _pendingLogout = true;
    final tombstone = _record(logout: true);
    _user = null;
    if (!_disposed) {
      _events.add(const IdentityEvent(type: IdentityEventType.signedOut));
    }
    await _persist(tombstone);
    _cancelSaveFailed = false;
  }

  Future<void> _finishLogout() async {
    await _cancelSave;
    if (_cancelSaveFailed) {
      throw const IdentityFailure(IdentityFailureCode.storage);
    }
    try {
      await session.logout(_refresh);
    } on AppClientFailure catch (error) {
      if (error.status != 401) throw _failure(error);
    }
    await _persist(null);
    _pendingLogout = false;
    _refresh = null;
  }

  @override
  Future<void> signOut() async {
    try {
      await clearLocalSession();
    } catch (_) {
      // A failed vault write must not prevent an independent server revocation
      // attempt. Keep reporting storage failure; never pretend local cleanup
      // succeeded or reuse this credential for another login.
      try {
        await session.logout(_refresh);
      } catch (_) {
        /* The caller must retry local cleanup; no credential is published. */
      }
      throw const IdentityFailure(IdentityFailureCode.storage);
    }
    try {
      await _finishLogout();
    } catch (_) {
      throw const IdentityFailure(IdentityFailureCode.remoteSignOutUnconfirmed);
    }
  }

  static IdentityFailure _failure(Object error) {
    if (error is IdentityFailure) return error;
    if (error is TimeoutException) {
      return const IdentityFailure(IdentityFailureCode.timeout);
    }
    if (error is! AppClientFailure) {
      return const IdentityFailure(IdentityFailureCode.unknown);
    }
    return IdentityFailure(switch (error.code) {
      'otp_required' => IdentityFailureCode.otpRequired,
      'invalid_otp' => IdentityFailureCode.invalidOtp,
      'invalid_credentials' => IdentityFailureCode.invalidCredentials,
      'account_denied' => IdentityFailureCode.accountDenied,
      'password_change_required' => IdentityFailureCode.passwordChangeRequired,
      'cancelled' => IdentityFailureCode.cancelled,
      'timeout' => IdentityFailureCode.timeout,
      'provider_timeout' => IdentityFailureCode.timeout,
      'network' => IdentityFailureCode.network,
      'storage' => IdentityFailureCode.storage,
      _ => switch (error.status) {
        401 => IdentityFailureCode.sessionRejected,
        403 => IdentityFailureCode.accountDenied,
        429 => IdentityFailureCode.rateLimited,
        int value when value >= 500 => IdentityFailureCode.providerUnavailable,
        _ => IdentityFailureCode.unknown,
      },
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    cancelRequests();
    _disposed = true;
    session.client.close();
    await _events.close();
  }
}
