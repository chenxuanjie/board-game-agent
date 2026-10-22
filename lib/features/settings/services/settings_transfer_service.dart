import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webdav_settings/webdav_settings.dart';

import '../../../app/state/app_controller.dart';
import '../../assistant/models/ai_api_config.dart';
import '../../library/models/asset_source_config.dart';
import '../../library/services/board_game_remote_layout.dart';
import '../models/configuration_transfer.dart';
import '../../identity/services/account_service.dart';
import '../../identity/models/account_configuration.dart';

abstract interface class ConfigurationTransferJournal {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
  Future<void> clear();
}

class SecureConfigurationTransferJournal
    implements ConfigurationTransferJournal {
  const SecureConfigurationTransferJournal({
    this.storage = const FlutterSecureStorage(),
  });
  final FlutterSecureStorage storage;
  static const key = 'board_game_agent.configuration_import_v1';
  @override
  Future<Map<String, dynamic>?> read() async {
    final text = await storage.read(key: key);
    if (text == null) return null;
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      // Avoid attaching the sensitive snapshot to a parse error or startup log.
      throw const FormatException('Invalid configuration recovery record');
    }
  }

  @override
  Future<void> write(Map<String, dynamic> value) =>
      storage.write(key: key, value: jsonEncode(value));
  @override
  Future<void> clear() => storage.delete(key: key);
}

/// Coordinates existing stores; the journal closes interrupted multi-store writes.
/// Secrets in rollback snapshots use the existing secure-storage dependency.
class SettingsTransferService {
  SettingsTransferService({
    required this.controller,
    this.webDav,
    this.account,
    ConfigurationTransferJournal? journal,
  }) : journal = journal ?? const SecureConfigurationTransferJournal();
  final AccountService? account;
  final AppController controller;
  final WebDavSettingsController? webDav;
  final ConfigurationTransferJournal journal;
  bool _busy = false;
  bool get isBusy =>
      _busy ||
      account?.isBusy == true ||
      webDav?.isSaving == true ||
      webDav?.isTesting == true;

  Future<void> recover() async {
    final pending = await journal.read();
    if (pending == null) return;
    if (pending['committed'] != true) await _restore(pending);
    await journal.clear();
  }

  Future<void> apply({
    AiApiConfig? ai,
    WebDavSettings? dav,
    bool activateWebDav = false,
    AssetSourceConfig? resourceSource,
    AccountConfiguration? connections,
  }) async {
    if (isBusy) {
      throw const ConfigurationTransferException(
        '配置正在保存或检测，请稍后再试。',
        'Configuration is busy. Try again shortly.',
      );
    }
    if (ai == null && dav == null) {
      throw const ConfigurationTransferException(
        '请选择要导入的配置。',
        'Select a configuration to import.',
      );
    }
    if (dav != null && webDav == null) {
      throw const ConfigurationTransferException(
        '当前入口无法保存 WebDAV，请从设置页进入。',
        'Open this feature from Settings to save WebDAV.',
      );
    }
    if (ai != null) {
      ConfigurationTransfer.aiConfig(
        ai.toMap().map((key, value) => MapEntry(key, value as String)),
      );
    }
    if (dav != null) {
      ConfigurationTransfer.validateUrl(dav.baseUrl);
      if (account == null &&
          dav.username.trim().isEmpty != dav.password.isEmpty) {
        throw const ConfigurationTransferException(
          'WebDAV 账号与密码需同时填写或同时留空。',
          'Provide both WebDAV username and password, or leave both empty.',
        );
      }
    }
    _busy = true;
    Map<String, dynamic>? snapshot;
    try {
      try {
        await recover();
      } catch (_) {
        throw const ConfigurationTransferException(
          '上次配置尚未恢复，请重试或重启。',
          'Previous configuration recovery is pending. Retry or restart.',
        );
      }
      snapshot = {
        'version': 1,
        'committed': false,
        if (ai != null) 'ai': controller.aiApiConfig.toMap(),
        if (dav != null) ...{
          'webdav': _davMap(webDav!.saved),
          if (account?.configuration != null)
            'account': account!.configuration!.toJson(),
          'sources': controller.assetSourceConfigs
              .map((source) => source.toMap())
              .toList(),
        },
      };
      await journal.write(snapshot);
      if (dav != null) {
        if (account?.configuration != null) {
          final current = account!.configuration!;
          AccountConfiguration next;
          if (connections != null) {
            next = current.edited(
              servers: connections.servers,
              folder: connections.storageFolder,
            );
          } else {
            final uri = Uri.parse(dav.baseUrl);
            if (uri.scheme != 'https') {
              throw const FormatException('HTTPS required');
            }
            final sources = current.resourceSources.toList();
            final id = resourceSource?.id ?? current.activeServer.id;
            final index = sources.indexWhere((s) => s.id == id);
            sources[index] = sources[index].copyWith(
              testUrl: dav.baseUrl,
              address: dav.baseUrl,
            );
            final migrated = AccountConfiguration.fromResources(
              sources: sources,
              previous: current,
            );
            next = current.edited(
              servers: migrated.servers,
              folder: AccountConfiguration.normalizeFolder(
                uri.pathSegments.where((s) => s.isNotEmpty).join('/'),
              ),
            );
          }
          await account!.saveConfiguration(next);
          if (account!.error != null) {
            throw StateError('Account connection pending');
          }
        } else {
          final next = BoardGameRemoteLayout.normalizeSettings(
            dav.copyWith(
              mode: activateWebDav
                  ? ExternalStorageMode.webDav
                  : ExternalStorageMode.localOnly,
            ),
          );
          await webDav!.saveConfiguration(next);
          final sources = controller.assetSourceConfigs.toList();
          final source = AssetSourceConfig(
            id: resourceSource?.id ?? 'configured_webdav',
            name: resourceSource?.name ?? 'WebDAV',
            address: next.baseUrl,
            testUrl: next.baseUrl,
          );
          final index = sources.indexWhere((item) => item.id == source.id);
          if (index >= 0) {
            sources[index] = source;
          } else {
            sources.insert(0, source);
          }
          if (activateWebDav) {
            sources.removeWhere((item) => item.id == source.id);
            sources.insert(0, source);
          }
          await controller.saveAssetSourceConfigs(sources);
        }
      }
      // Last write publishes the new model while preserving any running reply.
      if (ai != null) {
        await controller.saveAiApiConfig(
          ai,
          forNextRun: true,
          rememberPreset: false,
        );
      }
      await journal.write({...snapshot, 'committed': true});
      try {
        await journal.clear();
      } catch (_) {
        /* Committed records only need cleanup at startup. */
      }
    } catch (error) {
      if (snapshot == null && error is ConfigurationTransferException) rethrow;
      if (snapshot != null) {
        try {
          await _restore(snapshot);
          await journal.clear();
        } catch (_) {
          throw const ConfigurationTransferException(
            '保存未完成，恢复记录已保留。请重试；启动时也会恢复原配置。',
            'Saving did not complete. Recovery is pending; retry or restart to restore the previous configuration.',
          );
        }
      }
      throw const ConfigurationTransferException(
        '配置未能保存，原配置已保留，请重试。',
        'Configuration could not be saved. Previous settings were retained. Try again.',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _restore(Map<String, dynamic> snapshot) async {
    if (snapshot['version'] != 1) {
      throw const FormatException('Unsupported recovery version');
    }
    if (snapshot['webdav'] != null) {
      if (webDav == null) {
        throw StateError('WebDAV is required for recovery');
      }
      await webDav!.saveConfiguration(
        _davFromMap(Map<String, dynamic>.from(snapshot['webdav'] as Map)),
      );
      await controller.saveAssetSourceConfigs(
        (snapshot['sources'] as List)
            .map(
              (value) => AssetSourceConfig.fromMap(
                Map<String, dynamic>.from(value as Map),
              ),
            )
            .toList(),
      );
    }
    if (snapshot['account'] != null && account != null) {
      await account!.recoverConnectionConfiguration(
        AccountConfiguration.fromJson(
          Map<String, dynamic>.from(snapshot['account'] as Map),
        ),
      );
      if (account!.error != null) throw StateError('Account recovery pending');
    }
    if (snapshot['ai'] != null) {
      final values = Map<String, dynamic>.from(
        snapshot['ai'] as Map,
      ).map((key, value) => MapEntry(key, value as String));
      await controller.saveAiApiConfig(
        ConfigurationTransfer.aiConfig(values, validate: false),
        forNextRun: true,
        rememberPreset: false,
      );
    }
  }

  static Map<String, Object> _davMap(WebDavSettings settings) => {
    'mode': settings.mode.name,
    'baseUrl': settings.baseUrl,
    'username': settings.username,
    'password': settings.password,
  };
  static WebDavSettings _davFromMap(Map<String, dynamic> map) => WebDavSettings(
    mode: ExternalStorageMode.values.byName(map['mode'] as String),
    baseUrl: map['baseUrl'] as String,
    username: map['username'] as String,
    password: map['password'] as String,
  );
}
