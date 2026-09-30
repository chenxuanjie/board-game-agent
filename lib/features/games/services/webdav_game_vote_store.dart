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
  WebDavGameVoteStore(this.settings, {http.Client? httpClient})
    : _httpClient = httpClient;

  final WebDavSettings settings;
  final http.Client? _httpClient;
  static const directory =
      '${BoardGameRemoteLayout.appRoot}/votes/${GameVoteBallot.campaign}';
  WebDavStorageClient? _client;
  bool _closed = false;

  static RemoteGameVoteStore? fromSettings(WebDavSettings settings) =>
      settings.mode == ExternalStorageMode.webDav && settings.isComplete
      ? WebDavGameVoteStore(BoardGameRemoteLayout.normalizeSettings(settings))
      : null;

  @override
  String get scope => sha256
      .convert(
        utf8.encode('${settings.baseUrl.trim()}\n${settings.username.trim()}'),
      )
      .toString();

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
    await _storage.ensureDirectory(directory);
    if (_closed) throw StateError('Vote store is closed');
    await _storage.uploadText(
      '$directory/${ballot.deviceId}.json',
      ballot.encode(),
      contentType: 'application/json; charset=utf-8',
    );
  }

  @override
  Future<List<GameVoteBallot>> readBallots() async {
    final entries = (await _storage.list(directory))
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
              await _storage.downloadText('$directory/${entry.name}'),
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
