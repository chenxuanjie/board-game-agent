import 'dart:async';
import 'package:app_client/app_client.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite_async/sqlite_async.dart';
import 'board_worker_version.dart';

Future<PowerSyncDatabase> openBoardSyncDatabase(
  String filename,
  Schema schema,
) async {
  final path = kIsWeb
      ? filename
      : '${(await getApplicationSupportDirectory()).path}/$filename';
  final base = Uri.base;
  final db = PowerSyncDatabase(
    schema: schema,
    path: path,
    sqliteOptions: SqliteOptions(
      webSqliteOptions: WebSqliteOptions(
        wasmUri: base.resolve('powersync/sqlite3.wasm').toString(),
        workerUri: base
            .resolve('powersync/powersync_db.worker.js')
            .replace(queryParameters: {'v': boardWorkerVersion})
            .toString(),
      ),
    ),
  );
  try {
    await db.initialize().timeout(const Duration(seconds: 15));
    return db;
  } catch (_) {
    unawaited(
      db.close().timeout(const Duration(seconds: 5)).catchError((Object _) {}),
    );
    rethrow;
  }
}

PowerSyncCredentials boardSyncCredentials(
  AppJsonClient client,
  Map<String, dynamic> data, {
  required String userId,
  String? syncScope,
}) {
  final endpoint = Uri.parse(data['endpoint'] as String);
  final browserProxy = client.baseUri.path == '/api/';
  if (data['user_id'] != userId ||
      data['app_id'] != 'board_game_agent' ||
      data['sync_scope'] != syncScope ||
      !['http', 'https'].contains(endpoint.scheme) ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      !browserProxy && endpoint.origin != client.origin.origin) {
    throw StateError('Sync identity mismatch');
  }
  return PowerSyncCredentials.fromJson({
    ...data,
    'endpoint': browserProxy
        ? client.baseUri.resolve('powersync/').toString()
        : '${(data['endpoint'] as String).replaceFirst(RegExp(r'/+$'), '')}/',
  });
}
