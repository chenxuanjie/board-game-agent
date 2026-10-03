import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:webdav_settings/webdav_settings.dart';
import 'package:webdav_storage/webdav_storage.dart';

import '../../library/services/board_game_remote_layout.dart';
import '../models/game_vote_record.dart';

abstract interface class RemoteGameVoteStore {
  String get scope;
  Future<void> upload(GameVoteBallot ballot);
  Future<List<GameVoteBallot>> readBallots();
  void close();
}

/// Uses the existing shared WebDAV client and browser proxy configuration.
class WebDavGameVoteStore implements RemoteGameVoteStore {
  WebDavGameVoteStore(
    this.settings, {
    http.Client? httpClient,
    this.namespace = GameVoteBallot.campaign,
  }) : _httpClient = httpClient;

  final WebDavSettings settings;
  final String namespace;
  final http.Client? _httpClient;
  static const directory =
      '${BoardGameRemoteLayout.appRoot}/votes/${GameVoteBallot.campaign}';
  String get _directory => '${BoardGameRemoteLayout.appRoot}/votes/$namespace';
  WebDavStorageClient? _client;
  bool _closed = false;

  static RemoteGameVoteStore? fromSettings(
    WebDavSettings settings, {
    String namespace = GameVoteBallot.campaign,
  }) => settings.mode == ExternalStorageMode.webDav && settings.isComplete
      ? WebDavGameVoteStore(
          BoardGameRemoteLayout.normalizeSettings(settings),
          namespace: namespace,
        )
      : null;

  @override
  String get scope => scopeFor(settings, namespace: namespace)!;

  static String? scopeFor(
    WebDavSettings settings, {
    String namespace = GameVoteBallot.campaign,
  }) {
    if (settings.baseUrl.trim().isEmpty) return null;
    final normalized = BoardGameRemoteLayout.normalizeSettings(settings);
    return sha256
        .convert(
          utf8.encode(
            '${normalized.baseUrl.trim()}\n${normalized.username.trim()}${namespace == GameVoteBallot.campaign ? '' : '\n$namespace'}',
          ),
        )
        .toString();
  }

  WebDavStorageClient get _storage {
    if (_closed) throw StateError('Vote store is closed');
    return _client ??= WebDavStorageClient(
      httpClient: _httpClient,
      config: WebDavConfig(
        baseUri: Uri.parse(settings.baseUrl.trim()),
        username: settings.username.trim().isEmpty
            ? null
            : settings.username.trim(),
        password: settings.password.isEmpty ? null : settings.password,
        timeout: const Duration(seconds: 6),
        proxyUri: kIsWeb ? Uri.base.resolve('/webdav-proxy') : null,
      ),
    );
  }

  @override
  Future<void> upload(GameVoteBallot ballot) async {
    if (!GameVoteBallot.namespacePattern.hasMatch(namespace) ||
        ballot.namespace != namespace) {
      throw const FormatException('Reaction namespace mismatch');
    }
    await _storage.ensureDirectory(_directory);
    if (_closed) throw StateError('Vote store is closed');
    await _storage.uploadText(
      '$_directory/${ballot.deviceId}.json',
      ballot.encode(),
      contentType: 'application/json; charset=utf-8',
    );
  }

  @override
  Future<List<GameVoteBallot>> readBallots() async {
    if (!GameVoteBallot.namespacePattern.hasMatch(namespace)) {
      throw const FormatException('Invalid reaction namespace');
    }
    final entries = (await _storage.list(_directory))
        .where(
          (entry) =>
              !entry.isCollection &&
              entry.name.endsWith('.json') &&
              GameVoteBallot.devicePattern.hasMatch(
                entry.name.substring(0, entry.name.length - 5),
              ),
        )
        .toList();
    if (entries.length > 1000) {
      throw StateError('Vote directory limit exceeded');
    }
    final ballots = <GameVoteBallot>[];
    // Bound simultaneous requests and reject incomplete snapshots.
    for (var start = 0; start < entries.length; start += 8) {
      final batch = entries.skip(start).take(8);
      ballots.addAll(
        await Future.wait(
          batch.map((entry) async {
            final ballot = GameVoteBallot.decode(
              await _storage.downloadText('$_directory/${entry.name}'),
              namespace: namespace,
            );
            if ('${ballot.deviceId}.json' != entry.name) {
              throw const FormatException('Ballot filename mismatch');
            }
            return ballot;
          }),
        ),
      );
    }
    return ballots;
  }

  @override
  void close() {
    _closed = true;
    _client?.close();
  }
}
