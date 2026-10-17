import 'dart:async';
import 'dart:convert';

import 'package:app_identity/app_identity.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account_configuration.dart';
import 'web_sync_files.dart';

/// Browser identity uses an opaque HttpOnly cookie owned by the same-origin
/// server. Passwords, DSM SIDs and SynoToken are never persisted in JavaScript.
final class WebAccountGateway
    implements
        IdentityGateway,
        IdentityVerifiedSignInGateway,
        IdentityLocalSessionCleanup {
  WebAccountGateway({http.Client? client, Uri? site})
    : _client = client ?? http.Client(),
      _site = site ?? Uri.base;

  static const _logoutKey = 'board_game_agent.web_account.logout_pending.v1';
  final http.Client _client;
  final Uri _site;
  final _events = StreamController<IdentityEvent>.broadcast();
  Completer<void> _abort = Completer<void>();
  int _generation = 0;
  bool _disposed = false;
  IdentityUser? _user;
  int? _nasUid;
  int? get nasUid => _user == null ? null : _nasUid;

  WebSyncTransport _syncTransport(String lane) {
    final id = _user?.id;
    final uid = nasUid;
    final generation = _generation;
    if (id == null || uid == null) {
      throw const PrivateFileException(PrivateFileFailure.session);
    }
    return WebSyncTransport(
      client: _client,
      site: _site,
      lane: lane,
      uid: uid,
      isActive: () =>
          !_disposed &&
          _generation == generation &&
          _user?.id == id &&
          nasUid == uid,
    );
  }

  AccountPrivateFiles privateFiles() =>
      WebPrivateSyncFiles(_syncTransport('private'));
  AccountPublicFiles publicFiles() =>
      WebPublicSyncFiles(_syncTransport('public'), uid: nasUid!);

  static Future<AccountConfiguration> loadConfiguration({
    http.Client? client,
    Uri? site,
  }) async {
    final gateway = WebAccountGateway(client: client, site: site);
    try {
      final value = await gateway._request('config');
      if (value['version'] != 1) {
        throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
      }
      return AccountConfiguration(
        nasOrigin: Uri.parse(value['nasOrigin'] as String),
        identityOrigin: Uri.parse(value['identityOrigin'] as String),
        storageFolder: value['storageFolder'] as String? ?? 'friend',
      );
    } on IdentityFailure {
      rethrow;
    } catch (_) {
      throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
    } finally {
      await gateway.dispose();
    }
  }

  @override
  IdentityUser? get cachedUser => _user;
  @override
  Stream<IdentityEvent> get changes => _events.stream;

  Future<Map<String, dynamic>> _request(
    String endpoint, {
    Map<String, Object>? body,
  }) async {
    if (_disposed) throw const IdentityFailure(IdentityFailureCode.cancelled);
    final generation = _generation;
    final request =
        http.AbortableRequest(
            body == null ? 'GET' : 'POST',
            _site.resolve('/api/account/$endpoint'),
            abortTrigger: _abort.future,
          )
          ..headers.addAll({
            'Accept': 'application/json',
            'X-Board-Game-Request': '1',
          });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      return await (() async {
        final response = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          bytes.addAll(chunk);
          if (bytes.length > 16384) {
            throw const IdentityFailure(
              IdentityFailureCode.providerUnavailable,
            );
          }
        }
        if (_disposed || generation != _generation) {
          throw const IdentityFailure(IdentityFailureCode.cancelled);
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) {
          throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
        }
        if (response.statusCode != 200) {
          final code = IdentityFailureCode.values
              .where((v) => v.name == decoded['error'])
              .firstOrNull;
          throw IdentityFailure(
            code ?? IdentityFailureCode.providerUnavailable,
          );
        }
        return decoded;
      })().timeout(Duration(seconds: endpoint == 'logout' ? 4 : 22));
    } on IdentityFailure {
      rethrow;
    } on TimeoutException {
      if (!_abort.isCompleted) _abort.complete();
      _abort = Completer<void>();
      throw const IdentityFailure(IdentityFailureCode.timeout);
    } on http.RequestAbortedException {
      throw const IdentityFailure(IdentityFailureCode.cancelled);
    } on http.ClientException {
      throw const IdentityFailure(IdentityFailureCode.network);
    } catch (_) {
      throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
    }
  }

  IdentityUser? _decodeUser(Map<String, dynamic> value) {
    _nasUid = null;
    if (value['user'] == null && value.containsKey('user')) return null;
    final user = value['user'];
    if (user is! Map<String, dynamic> ||
        user['id'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(user['id'] as String) ||
        user['displayName'] is! String ||
        (user['displayName'] as String).isEmpty ||
        (user['displayName'] as String).length > 200) {
      throw const IdentityFailure(IdentityFailureCode.providerUnavailable);
    }
    if (user['uid'] is int && (user['uid'] as int) > 0) {
      _nasUid = user['uid'] as int;
    }
    return IdentityUser(
      id: user['id'] as String,
      displayName: user['displayName'] as String,
    );
  }

  Future<void> _clearLogout() async {
    if (!await (await SharedPreferences.getInstance()).remove(_logoutKey)) {
      throw const IdentityFailure(IdentityFailureCode.storage);
    }
  }

  @override
  Future<IdentityUser?> verifyCurrentUser() async {
    if ((await SharedPreferences.getInstance()).getBool(_logoutKey) == true) {
      await _request('logout', body: {});
      await _clearLogout();
    }
    final value = await _request('session');
    return _user = _decodeUser(value);
  }

  @override
  Future<IdentityUser> signIn({
    required String account,
    required String password,
    String? otp,
  }) async {
    final generation = _generation;
    // Establish an anonymous HttpOnly session before starting a credential
    // request. Logout can invalidate an in-flight login using the same cookie.
    await verifyCurrentUser();
    if (_disposed || generation != _generation) {
      throw const IdentityFailure(IdentityFailureCode.cancelled);
    }
    if (_user != null) {
      throw const IdentityFailure(IdentityFailureCode.sessionRejected);
    }
    try {
      final value = await _request(
        'login',
        body: {'account': account, 'password': password, 'otp': ?otp},
      );
      final verified = _decodeUser(value);
      if (verified == null) {
        throw const IdentityFailure(IdentityFailureCode.sessionRejected);
      }
      return _user = verified;
    } on IdentityFailure catch (failure) {
      if (_disposed || generation != _generation) rethrow;
      // OTP and rejected passwords never created a server identity. For an
      // interrupted/ambiguous response, prevent restoration until logout wins.
      if (!const {
        IdentityFailureCode.otpRequired,
        IdentityFailureCode.invalidOtp,
        IdentityFailureCode.invalidCredentials,
        IdentityFailureCode.accountDenied,
        IdentityFailureCode.rateLimited,
        IdentityFailureCode.passwordChangeRequired,
      }.contains(failure.code)) {
        await clearLocalSession();
        if (!_disposed && generation == _generation) {
          try {
            await _request('logout', body: {});
            if (!_disposed && generation == _generation) await _clearLogout();
          } catch (_) {
            // Durable non-secret tombstone blocks restoration on reload.
          }
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> clearLocalSession() async {
    _user = null;
    if (!await (await SharedPreferences.getInstance()).setBool(
      _logoutKey,
      true,
    )) {
      throw const IdentityFailure(IdentityFailureCode.localCleanupFailed);
    }
    if (!_disposed) {
      _events.add(const IdentityEvent(type: IdentityEventType.signedOut));
    }
  }

  @override
  Future<void> signOut() async {
    cancelRequests();
    await clearLocalSession();
    await _request('logout', body: {});
    await _clearLogout();
  }

  @override
  void cancelRequests() {
    _generation++;
    if (!_abort.isCompleted) _abort.complete();
    _abort = Completer<void>();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    cancelRequests();
    _disposed = true;
    _client.close();
    await _events.close();
  }
}
