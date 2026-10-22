import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:webdav_storage/webdav_storage.dart';
import 'package:webdav_sync/webdav_sync.dart';

/// Reuses the shared operation protocol. FileStation provides authenticated
/// private-home storage without saving another password. New records are files
/// in one pre-provisioned directory; legacy device directories are read only.
final class AccountSyncRemoteStore implements SyncRemoteStore {
  AccountSyncRemoteStore({
    required this.files,
    required this.datasetId,
    this.root = 'operations',
  });
  final AccountPrivateFiles files;
  final String datasetId, root;
  String _file(SyncOperation op) =>
      '$root/${op.deviceId}.${op.sequence.toString().padLeft(16, '0')}.json';
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
          PrivateFileFailure.missing => 404,
          PrivateFileFailure.network || PrivateFileFailure.timeout => null,
          PrivateFileFailure.cancelled => 409,
          _ => 503,
        },
      );
    }
  }

  @override
  Future<SyncRemoteSnapshot> read({required SyncCursor cursor}) =>
      _call(() async {
        final entries = await files.list(root);
        final records = <String, Map<int, List<String>>>{};
        var count = 0;
        void record(String device, String number, String path) {
          if (++count > 10000) {
            throw const SyncProtocolException('同步操作数量超过上限');
          }
          final sequence = int.parse(number);
          records
              .putIfAbsent(device, () => {})
              .putIfAbsent(sequence, () => [])
              .add(path);
          if (records.length > 128) {
            throw const SyncProtocolException('同步设备数量超过上限');
          }
        }

        for (final entry in entries) {
          if (entry.directory && _device(entry.name)) {
            // Compatibility only: never create, rename or remove these folders.
            records.putIfAbsent(entry.name, () => {});
            if (records.length > 128) {
              throw const SyncProtocolException('同步设备数量超过上限');
            }
            final legacy = await files.list('$root/${entry.name}');
            for (final file in legacy) {
              if (file.directory ||
                  !RegExp(r'^[0-9]{16}\.json$').hasMatch(file.name)) {
                throw const SyncProtocolException('云端操作名称非法');
              }
              record(
                entry.name,
                file.name.substring(0, 16),
                '$root/${entry.name}/${file.name}',
              );
            }
          } else {
            final match = RegExp(
              r'^(d[0-9a-f]{32})\.([0-9]{16})\.json$',
            ).firstMatch(entry.name);
            if (entry.directory || match == null) {
              throw const SyncProtocolException('云端操作名称非法');
            }
            record(match.group(1)!, match.group(2)!, '$root/${entry.name}');
          }
        }
        final heads = <String, SyncDeviceHead>{};
        final operations = <SyncOperation>[];
        for (final device in records.keys.toList()..sort()) {
          final sequences = records[device]!.keys.toList()..sort();
          var expected = 1;
          for (final sequence in sequences) {
            if (sequence != expected++) {
              throw const SyncProtocolException('云端操作序列不连续');
            }
          }
          for (final sequence in sequences) {
            if (sequence <= cursor.forDevice(device)) continue;
            if (operations.length >= 100) break;
            SyncOperation? operation;
            for (final path in records[device]![sequence]!) {
              final text = await files.read(path);
              final op = SyncOperation.fromJson(
                Map<String, Object?>.from(jsonDecode(text) as Map),
              );
              if (op.datasetId != datasetId ||
                  op.deviceId != device ||
                  op.sequence != sequence) {
                throw const SyncProtocolException('云端账号或操作范围不匹配');
              }
              if (operation != null &&
                  operation.canonicalJson != op.canonicalJson) {
                throw const SyncProtocolException('新旧路径的同步记录冲突');
              }
              operation = op;
            }
            final op = operation!;
            operations.add(op);
            heads[device] = SyncDeviceHead(
              deviceId: device,
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
      });
  @override
  Future<SyncAppendResult> append(SyncOperation op) => _call(() async {
    if (op.datasetId != datasetId || !_device(op.deviceId)) {
      throw const SyncProtocolException('拒绝跨账号写入');
    }
    await files.createImmutable(_file(op), op.canonicalJson);
    return const SyncAppendResult(SyncAppendStatus.created);
  });
}
