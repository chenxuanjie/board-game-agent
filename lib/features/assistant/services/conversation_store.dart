import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/services/preferences_service.dart';

/// Retains the native v4 file location; Web uses browser-backed preferences.
/// The controller serializes writes to this store.
class ConversationStore {
  const ConversationStore({
    this.directory,
    this.browserStorage = kIsWeb,
    this.identityUserId,
  });

  final Directory? directory;
  final bool browserStorage;
  final String? identityUserId;
  static const _browserKey = 'chat_conversations_v4';

  ConversationStore forIdentityScope(String? userId) {
    PreferencesService.validateIdentityUserId(userId);
    return userId == identityUserId
        ? this
        : ConversationStore(
            directory: directory,
            browserStorage: browserStorage,
            identityUserId: userId,
          );
  }

  String get _scopedBrowserKey {
    final scope = PreferencesService.identityStorageId(identityUserId);
    return scope == null ? _browserKey : 'personal_v1.$scope.$_browserKey';
  }

  Future<File> _file() async {
    final support = directory ?? await getApplicationSupportDirectory();
    final scope = PreferencesService.identityStorageId(identityUserId);
    final folder = scope == null
        ? support.path
        : '${support.path}${Platform.pathSeparator}personal_v1'
              '${Platform.pathSeparator}$scope';
    return File('$folder${Platform.pathSeparator}chat_conversations.json');
  }

  Future<String?> load() async {
    if (browserStorage) {
      return (await SharedPreferences.getInstance()).getString(
        _scopedBrowserKey,
      );
    }
    final file = await _file();
    return await file.exists() ? file.readAsString() : null;
  }

  Future<void> save(String payload) async {
    if (browserStorage) {
      if (!await (await SharedPreferences.getInstance()).setString(
        _scopedBrowserKey,
        payload,
      )) {
        throw StateError('Conversation storage write failed');
      }
      return;
    }
    final file = await _file();
    await file.parent.create(recursive: true);
    final staged = File('${file.path}.tmp');
    await staged.writeAsString(payload, flush: true);
    // Commit only a complete JSON snapshot; a failed write leaves the old file.
    await staged.rename(file.path);
  }
}
