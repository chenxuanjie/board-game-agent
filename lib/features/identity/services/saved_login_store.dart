import 'dart:convert';

import 'package:app_identity/app_identity.dart';

/// Login suggestions are independent of sessions and active WebDAV credentials.
/// The entire bounded history, including optional passwords, uses secure storage.
final class SavedLogin {
  const SavedLogin({
    required this.environment,
    required this.username,
    this.password,
    this.serverId,
  });

  final String environment;
  final String username;
  final String? password;
  final String? serverId;
  bool get hasPassword => password?.isNotEmpty == true;

  Map<String, dynamic> toJson() => {
    'environment': environment,
    'username': username,
    if (hasPassword) 'password': password,
    if (serverId != null) 'serverId': serverId,
  };

  factory SavedLogin.fromJson(Map<String, dynamic> value) {
    final entry = SavedLogin(
      environment: value['environment'] as String,
      username: (value['username'] as String).trim(),
      password: value['password'] as String?,
      serverId: value['serverId'] as String?,
    );
    if (entry.environment.isEmpty || entry.username.isEmpty) {
      throw const FormatException('Invalid saved login');
    }
    return entry;
  }
}

final class SavedLoginStore {
  SavedLoginStore({IdentitySessionStorage? storage}) : _storage = storage;

  IdentitySessionStorage get _secureStorage =>
      _storage ??= SecureIdentitySessionStorage(
        appId: 'board_game_agent_logins',
        environment: 'saved_accounts_v1',
      );

  static const capacity = 10;
  IdentitySessionStorage? _storage;
  List<SavedLogin> _entries = const [];
  List<SavedLogin> get entries => _entries;
  bool _loaded = false;
  Future<void> _tail = Future<void>.value();

  Future<void> _run(Future<void> Function() operation) {
    final work = _tail.then((_) => operation());
    _tail = work.catchError((Object _) {});
    return work;
  }

  Future<void> _load() async {
    if (_loaded) return;
    final raw = await _secureStorage.read();
    if (raw != null) {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      if (value['version'] != 1) {
        throw const FormatException('Unsupported saved login history');
      }
      final seen = <(String, String)>{};
      _entries = List.unmodifiable(
        (value['accounts'] as List)
            .map((v) => SavedLogin.fromJson(v as Map<String, dynamic>))
            .where((e) => seen.add((e.environment, e.username)))
            .take(capacity),
      );
    }
    _loaded = true;
  }

  Future<void> load() => _loaded ? Future<void>.value() : _run(_load);

  Future<void> remember({
    required String environment,
    required String username,
    required String password,
    required bool savePassword,
    String? serverId,
  }) => _run(() async {
    await _load();
    final entry = SavedLogin(
      environment: environment,
      username: username.trim(),
      password: savePassword ? password : null,
      serverId: serverId,
    );
    final next = [
      entry,
      ..._entries.where(
        (e) =>
            e.environment != entry.environment || e.username != entry.username,
      ),
    ].take(capacity).toList();
    await _write(next);
  });

  Future<void> forget(SavedLogin entry) => _run(() async {
    await _load();
    await _write(
      _entries
          .where(
            (e) =>
                e.environment != entry.environment ||
                e.username != entry.username,
          )
          .toList(),
    );
  });

  Future<void> _write(List<SavedLogin> next) async {
    await _secureStorage.write(
      jsonEncode({
        'version': 1,
        'accounts': next.map((e) => e.toJson()).toList(),
      }),
    );
    _entries = List.unmodifiable(next);
  }
}
