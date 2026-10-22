import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:webdav_settings/webdav_settings.dart';

import '../../../core/localization/app_copy.dart';
import '../../assistant/models/ai_api_config.dart';
import '../../assistant/models/ai_model_policy.dart';

enum ConfigurationScope { all, ai, webDav }

class ConfigurationTransferException implements Exception {
  const ConfigurationTransferException(this.zh, this.en);
  final String zh;
  final String en;
  String message(AppCopy copy) => copy.localized(zh, en);
}

class UnassignedConfigurationField {
  const UnassignedConfigurationField(this.label, this.value);
  final String label;
  final String value;
}

class ConfigurationImport {
  ConfigurationImport({
    Map<String, String>? ai,
    Map<String, String>? webDav,
    List<UnassignedConfigurationField>? unassigned,
  }) : ai = ai ?? {},
       webDav = webDav ?? {},
       unassigned = unassigned ?? [];
  final Map<String, String> ai;
  final Map<String, String> webDav;
  final List<UnassignedConfigurationField> unassigned;
  bool get isEmpty => ai.isEmpty && webDav.isEmpty && unassigned.isEmpty;
}

/// Offline, bounded parsing. No clipboard polling, model call or HTTP request.
abstract final class ConfigurationTransfer {
  static const prefix = 'BGA1:';
  static const maxLength = 65536;
  static const aiFields = [
    'name',
    'baseUrl',
    'apiKey',
    'model',
    'apiKeyHeader',
    'chatPath',
    'reasoningEffort',
    'responseSpeed',
  ];
  static const webDavFields = [
    'baseUrl',
    'username',
    'password',
    'connections',
  ];

  static String label(String key, AppCopy copy) => switch (key) {
    'name' => copy.localized('服务名称', 'Service name'),
    'baseUrl' => copy.localized('地址', 'URL'),
    'apiKey' => 'API Key',
    'model' => copy.localized('模型', 'Model'),
    'apiKeyHeader' => copy.localized('密钥请求头', 'Key header'),
    'chatPath' => copy.localized('请求路径', 'Request path'),
    'reasoningEffort' => copy.localized('推理强度', 'Reasoning effort'),
    'responseSpeed' => copy.localized('服务等级', 'Service tier'),
    'username' => copy.localized('账号', 'Username'),
    'password' => copy.localized('密码', 'Password'),
    'connections' => copy.localized('服务器配置', 'Server configuration'),
    _ => key,
  };

  static Map<String, Object> payload(
    AiApiConfig ai,
    WebDavSettings? webDav,
    ConfigurationScope scope, {
    bool includeSecrets = false,
  }) => {
    'format': 'board-game-agent.settings',
    'version': 1,
    if (scope != ConfigurationScope.webDav)
      'ai': {...ai.toMap()}
        ..removeWhere((key, _) => !includeSecrets && key == 'apiKey'),
    if (scope != ConfigurationScope.ai && webDav != null)
      'webdav': {
        'baseUrl': webDav.baseUrl,
        'username': webDav.username,
        if (includeSecrets) 'password': webDav.password,
      },
  };

  static String encode(Map<String, Object> payload) {
    final json = jsonEncode(payload);
    return '$prefix${base64Url.encode(utf8.encode(jsonEncode({'payload': payload, 'checksum': sha256.convert(utf8.encode(json)).toString()})))}';
  }

  static String readable(Map<String, Object> payload, AppCopy copy) {
    final lines = <String>[];
    for (final group in ['ai', 'webdav']) {
      final values = payload[group];
      if (values is! Map) continue;
      if (lines.isNotEmpty) lines.add('');
      lines.add(group == 'ai' ? '[AI]' : '[WebDAV]');
      for (final entry in values.entries) {
        // JSON quoted strings round-trip colons, spaces and multiline passwords.
        lines.add(
          '${label(entry.key as String, copy)}: ${jsonEncode(entry.value)}',
        );
      }
    }
    return lines.join('\n');
  }

  static ConfigurationImport parse(String input) {
    if (input.length > maxLength) {
      throw const ConfigurationTransferException(
        '内容过长，请只粘贴配置。',
        'Paste only configuration; the text is too long.',
      );
    }
    final text = input.trim();
    if (text.isEmpty) {
      throw const ConfigurationTransferException(
        '请先粘贴配置。',
        'Paste a configuration first.',
      );
    }
    final code = RegExp(r'BGA\d+:\S+').firstMatch(text)?.group(0);
    if (code != null) {
      if (!code.startsWith(prefix)) {
        throw const ConfigurationTransferException(
          '配置码版本暂不支持。',
          'This configuration code version is unsupported.',
        );
      }
      try {
        final decoded = jsonDecode(
          utf8.decode(
            base64Url.decode(
              base64Url.normalize(code.substring(prefix.length)),
            ),
          ),
        );
        if (decoded is! Map<String, dynamic> ||
            decoded['payload'] is! Map<String, dynamic>) {
          throw const FormatException();
        }
        final payload = decoded['payload'] as Map<String, dynamic>;
        if (decoded['checksum'] !=
            sha256.convert(utf8.encode(jsonEncode(payload))).toString()) {
          throw const FormatException();
        }
        return _structured(payload);
      } on ConfigurationTransferException {
        rethrow;
      } catch (_) {
        throw const ConfigurationTransferException(
          '配置码不完整或已损坏，请重新复制。',
          'The configuration code is incomplete or damaged. Copy it again.',
        );
      }
    }
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        return _structured(decoded);
      } on ConfigurationTransferException {
        rethrow;
      } catch (_) {
        throw const ConfigurationTransferException(
          'JSON 配置格式不正确。',
          'Invalid JSON configuration.',
        );
      }
    }
    final result = ConfigurationImport();
    String? section;
    for (var line in text.split(RegExp(r'[\r\n]+'))) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('```')) continue;
      final heading = line
          .replaceAll(RegExp(r'[\[\]【】:#：\s]'), '')
          .toLowerCase();
      if (['ai', 'ai设置', 'ai配置', 'ai服务'].contains(heading)) {
        section = 'ai';
        continue;
      }
      if (['webdav', 'webdav设置', 'webdav配置'].contains(heading)) {
        section = 'webdav';
        continue;
      }
      if (RegExp(r'^https?://', caseSensitive: false).hasMatch(line)) {
        _put(result, section, 'baseUrl', line, 'URL');
        continue;
      }
      final match = RegExp(r'^([^:：=＝]+)\s*[:：=＝]\s*(.*)$').firstMatch(line);
      if (match == null) continue;
      var rawKey = match
          .group(1)!
          .trim()
          .replaceFirst(RegExp(r'^[-*•]\s*'), '');
      var value = match.group(2)!.trim();
      if (value.startsWith('"')) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is String) value = decoded;
        } catch (_) {
          /* Plain pasted text. */
        }
      }
      String? explicitGroup;
      if (RegExp(r'^webdav', caseSensitive: false).hasMatch(rawKey)) {
        explicitGroup = 'webdav';
        rawKey = rawKey.substring(6).trim();
      } else if (RegExp(
        r'^ai(?:$|\s|[._-]|地址|设置|服务|模型|密钥)',
        caseSensitive: false,
      ).hasMatch(rawKey)) {
        explicitGroup = 'ai';
        rawKey = rawKey.substring(2).trim();
      }
      final key = explicitGroup != null && rawKey.isEmpty
          ? 'baseUrl'
          : _aliases[_normalizeKey(rawKey)] ??
                _aliases[_normalizeKey(match.group(1)!)];
      if (key == null) {
        result.unassigned.add(
          UnassignedConfigurationField(match.group(1)!, value),
        );
        continue;
      }
      final group =
          explicitGroup ??
          ([
                'apiKey',
                'model',
                'apiKeyHeader',
                'chatPath',
                'reasoningEffort',
                'responseSpeed',
              ].contains(key)
              ? 'ai'
              : ['username', 'password'].contains(key)
              ? 'webdav'
              : section);
      _put(result, group, key, value, match.group(1)!);
    }
    // A single connection type makes a generic URL unambiguous. With both
    // connection types present, require explicit assignment instead of guessing.
    if (result.ai.isNotEmpty != result.webDav.isNotEmpty) {
      final group = result.ai.isNotEmpty ? 'ai' : 'webdav';
      final candidates = result.unassigned.toList();
      for (final field in candidates) {
        final key = _aliases[_normalizeKey(field.label)];
        if (key == 'baseUrl' &&
            !result.ai.containsKey('baseUrl') &&
            !result.webDav.containsKey('baseUrl')) {
          result.unassigned.remove(field);
          _put(result, group, key, field.value, field.label);
        }
      }
    }
    if (result.isEmpty) {
      throw const ConfigurationTransferException(
        '没有识别到配置，请使用带字段名的文本或配置码。',
        'No configuration found. Use labeled text or a configuration code.',
      );
    }
    return result;
  }

  static ConfigurationImport _structured(Map<String, dynamic> map) {
    if (map.containsKey('version') && map['version'] != 1) {
      throw const ConfigurationTransferException(
        '配置版本暂不支持。',
        'This configuration version is unsupported.',
      );
    }
    if (map.containsKey('format') &&
        map['format'] != 'board-game-agent.settings') {
      throw const FormatException();
    }
    final result = ConfigurationImport();
    if (map.containsKey('ai') ||
        map.containsKey('webdav') ||
        map.containsKey('webDav')) {
      for (final group in ['ai', 'webdav']) {
        final value = map[group] ?? (group == 'webdav' ? map['webDav'] : null);
        if (value == null) continue;
        if (value is! Map<String, dynamic>) throw const FormatException();
        for (final entry in value.entries) {
          if (entry.value is! String) throw const FormatException();
          final key = _aliases[_normalizeKey(entry.key)];
          if (key == null) {
            result.unassigned.add(
              UnassignedConfigurationField(
                '$group.${entry.key}',
                entry.value as String,
              ),
            );
            continue;
          }
          _put(
            result,
            group,
            key,
            entry.value as String,
            '$group.${entry.key}',
          );
        }
      }
    } else {
      for (final entry in map.entries) {
        if (entry.value is! String) throw const FormatException();
        final key = _aliases[_normalizeKey(entry.key)];
        _put(
          result,
          map.containsKey('apiKey') || map.containsKey('model')
              ? 'ai'
              : map.containsKey('username') || map.containsKey('password')
              ? 'webdav'
              : null,
          key,
          entry.value as String,
          entry.key,
        );
      }
    }
    if (result.isEmpty) throw const FormatException();
    return result;
  }

  static void _put(
    ConfigurationImport result,
    String? group,
    String? key,
    String value,
    String rawKey,
  ) {
    final fields = group == 'ai'
        ? result.ai
        : group == 'webdav'
        ? result.webDav
        : null;
    final allowed = group == 'ai' ? aiFields : webDavFields;
    if (fields == null ||
        key == null ||
        !allowed.contains(key) ||
        (fields.containsKey(key) && fields[key] != value)) {
      result.unassigned.add(UnassignedConfigurationField(rawKey, value));
      return;
    }
    fields[key] = value;
  }

  static String _normalizeKey(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[\s._-]'), '');
  static const _aliases = {
    'connections': 'connections',
    '服务器配置': 'connections',
    'name': 'name',
    '服务名称': 'name',
    'servicename': 'name',
    'provider': 'name',
    'baseurl': 'baseUrl',
    'url': 'baseUrl',
    '地址': 'baseUrl',
    '服务地址': 'baseUrl',
    '连接地址': 'baseUrl',
    'apikey': 'apiKey',
    'key': 'apiKey',
    '密钥': 'apiKey',
    'token': 'apiKey',
    'model': 'model',
    '模型': 'model',
    'apikeyheader': 'apiKeyHeader',
    'keyheader': 'apiKeyHeader',
    '密钥请求头': 'apiKeyHeader',
    'chatpath': 'chatPath',
    'requestpath': 'chatPath',
    '请求路径': 'chatPath',
    'reasoningeffort': 'reasoningEffort',
    '推理强度': 'reasoningEffort',
    'responsespeed': 'responseSpeed',
    'servicetier': 'responseSpeed',
    '服务等级': 'responseSpeed',
    'username': 'username',
    'user': 'username',
    '账号': 'username',
    '账户': 'username',
    '用户名': 'username',
    'password': 'password',
    'pass': 'password',
    '密码': 'password',
  };

  static Map<String, String> prepareAi(
    Map<String, String> patch,
    AiApiConfig current,
  ) {
    final values = current.toMap().map(
      (key, value) => MapEntry(key, value as String),
    );
    values.addAll(patch);
    if (patch.containsKey('baseUrl') &&
        patch['baseUrl']!.trim() != current.baseUrl.trim() &&
        !patch.containsKey('apiKey')) {
      values['apiKey'] = '';
    }
    return values;
  }

  static Map<String, String> prepareWebDav(
    Map<String, String> patch,
    WebDavSettings current,
  ) {
    final values = {
      'baseUrl': current.baseUrl,
      'username': current.username,
      'password': current.password,
      'connections': '',
    }..addAll(patch);
    if (patch.containsKey('baseUrl') &&
        patch['baseUrl']!.trim() != current.baseUrl.trim()) {
      if (!patch.containsKey('username')) values['username'] = '';
      if (!patch.containsKey('password')) values['password'] = '';
    }
    return values;
  }

  static AiApiConfig aiConfig(
    Map<String, String> values, {
    bool validate = true,
  }) {
    final config = AiApiConfig(
      name: values['name']!.trim(),
      baseUrl: values['baseUrl']!.trim(),
      apiKey: values['apiKey']!,
      model: values['model']!.trim(),
      apiKeyHeader: values['apiKeyHeader']!.trim(),
      chatPath: values['chatPath']!.trim(),
      reasoningEffort: AiReasoningEffortX.fromStored(values['reasoningEffort']),
      responseSpeed: AiResponseSpeedX.fromStored(values['responseSpeed']),
    );
    if (!validate) return config;
    validateUrl(config.baseUrl);
    if (config.apiKey.trim().isEmpty) {
      throw const ConfigurationTransferException(
        '请补充 AI 密钥；新地址不会沿用旧密钥。',
        'Enter the AI key. Old keys are not reused for a new URL.',
      );
    }
    if (config.name.isEmpty) {
      throw const ConfigurationTransferException(
        '请填写 AI 服务名称。',
        'Enter an AI service name.',
      );
    }
    if (config.model.isNotEmpty && !AiModelPolicy.allowsModel(config.model)) {
      throw const ConfigurationTransferException(
        '模型不在当前支持范围，请修改或留空后到设置中选择。',
        'This model is unsupported. Change it or leave it empty to select later.',
      );
    }
    if (config.apiKeyHeader != 'Authorization' ||
        config.chatPath != '/chat/completions') {
      throw const ConfigurationTransferException(
        '当前版本仅支持 Authorization 请求头与 /chat/completions 路径。',
        'This version supports Authorization and /chat/completions only.',
      );
    }
    if (!AiReasoningEffort.values.any(
          (e) => e.name == values['reasoningEffort'],
        ) ||
        ![
          'standard',
          'fast',
          'automatic',
          'default',
        ].contains(values['responseSpeed'])) {
      throw const ConfigurationTransferException(
        '推理强度或服务等级无法识别。',
        'Unrecognized reasoning effort or service tier.',
      );
    }
    final efforts = AiModelPolicy.reasoningEfforts(config.model);
    if (efforts != null &&
        config.reasoningEffort != AiReasoningEffort.automatic &&
        !efforts.contains(config.reasoningEffort)) {
      throw const ConfigurationTransferException(
        '所选模型不支持这一推理强度。',
        'The model does not support this reasoning effort.',
      );
    }
    return config;
  }

  static void validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw const ConfigurationTransferException(
        '请填写完整的 HTTP/HTTPS 地址，账号密码需分开填写。',
        'Enter an HTTP/HTTPS URL with credentials in separate fields.',
      );
    }
  }
}
