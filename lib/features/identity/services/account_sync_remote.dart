import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:webdav_storage/webdav_storage.dart';
import 'package:webdav_sync/webdav_sync.dart';

/// Reuses the shared operation protocol. FileStation provides authenticated
/// private-home storage without saving another password. Immutable per-device
/// files replace mutable DAV indexes, so concurrent devices cannot erase heads.
final class AccountSyncRemoteStore implements SyncRemoteStore {
  AccountSyncRemoteStore({
    required this.files,
    required this.datasetId,
    this.root = 'operations',
  });
  final AccountPrivateFiles files;
  final String datasetId, root;
  String _file(SyncOperation op) =>
      '$root/${op.deviceId}/${op.sequence.toString().padLeft(16, '0')}.json';
  static bool _device(String value) =>
      RegExp(r'^d[0-9a-f]{32}$').hasMatch(value);
  Future<T> _call<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on PrivateFileException catch (error) {
      throw WebDavException(
        operation: 'account-sync',
        uri: Uri.parse('https://private-nas.invalid'),
        message: '账号云同步连接失败',
        cause: error,
        statusCode: switch (error.failure) {
          PrivateFileFailure.denied || PrivateFileFailure.session => 403,
          PrivateFileFailure.network || PrivateFileFailure.timeout => null,
          PrivateFileFailure.cancelled => 409,
          _ => 503,
        },
      );
    }
  }

  @override
  Future<SyncRemoteSnapshot> read({required SyncCursor cursor}) => _call(
    () async {
      final devices = await files.list(root);
      if (devices.length > 128) throw const SyncProtocolException('同步设备数量超过上限');
      final heads = <String, SyncDeviceHead>{};
      final operations = <SyncOperation>[];
      for (final device in devices) {
        if (!device.directory || !_device(device.name)) {
          throw const SyncProtocolException('云端设备目录非法');
        }
        final records = await files.list('$root/${device.name}');
        final sequences = records.map((record) {
          if (record.directory ||
              !RegExp(r'^[0-9]{16}\.json$').hasMatch(record.name)) {
            throw const SyncProtocolException('云端操作名称非法');
          }
          return int.parse(record.name.substring(0, 16));
        }).toList()..sort();
        var expected = 1;
        for (final sequence in sequences) {
          if (sequence != expected++) {
            throw const SyncProtocolException('云端操作序列不连续');
          }
          if (sequence <= cursor.forDevice(device.name)) continue;
          if (operations.length >= 100) break;
          final text = await files.read(
            '$root/${device.name}/${sequence.toString().padLeft(16, '0')}.json',
          );
          final op = SyncOperation.fromJson(
            Map<String, Object?>.from(jsonDecode(text) as Map),
          );
          if (op.datasetId != datasetId ||
              op.deviceId != device.name ||
              op.sequence != sequence) {
            throw const SyncProtocolException('云端账号或操作范围不匹配');
          }
          operations.add(op);
          heads[device.name] = SyncDeviceHead(
            deviceId: device.name,
            sequence: sequence,
            operationId: op.operationId,
            updatedAt: op.changedAt,
          );
        }
      }
      return SyncRemoteSnapshot(
        manifest: SyncManifest(
          protocolVersion: 1,
          datasetId: datasetId,
          devices: heads,
          updatedAt: DateTime.now().toUtc(),
        ),
        operations: operations,
      );
    },
  );
  @override
  Future<SyncAppendResult> append(SyncOperation op) => _call(() async {
    if (op.datasetId != datasetId || !_device(op.deviceId)) {
      throw const SyncProtocolException('拒绝跨账号写入');
    }
    await files.createImmutable(_file(op), op.canonicalJson);
    return const SyncAppendResult(SyncAppendStatus.created);
  });
}
