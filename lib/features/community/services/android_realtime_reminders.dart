import 'dart:async';

import 'package:app_client/app_client.dart';
// ignore: implementation_imports
import 'package:app_ai_client/src/default_http_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'board_public_sync.dart';

/// Headless Android engine owned by the user-enabled foreground service.
/// Uses an isolated public database and never loads an account session.
Future<void> runAndroidRealtimeReminders() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('board_game_agent/realtime_reminders_service');
  AppJsonClient? client;
  BoardPublicSync? sync;
  var active = true;

  Future<void> closeResources() async {
    client?.cancelRequests();
    await sync?.close().catchError((Object _) {});
    client?.close();
    sync = null;
    client = null;
  }

  channel.setMethodCallHandler((call) async {
    if (call.method == 'stop') {
      active = false;
      await closeResources();
    }
  });
  try {
    final settings = await channel
        .invokeMapMethod<String, dynamic>('settings')
        .timeout(const Duration(seconds: 10));
    final origin = AppJsonClient.parseOrigin(settings?['origin'] as String);
    final generation = settings?['generation'] as int;
    var delaySeconds = 1;
    while (active) {
      try {
        final nextClient = AppJsonClient(
          origin,
          applicationId: 'board_game_agent',
          client: createDefaultAiHttpClient(),
          requestTimeout: const Duration(seconds: 20),
        );
        client = nextClient;
        final nextSync = await BoardPublicSync.open(
          client: nextClient,
          active: () => active,
          storageNamespace: 'board-reminder-public-v1',
          refresh: (_, _) async {},
          refreshPublications: (publications) async {
            if (!active || publications.isEmpty) return;
            await channel
                .invokeMethod<void>('publications', {
                  'origin': origin.origin,
                  'generation': generation,
                  'items': [
                    for (final item in publications)
                      {
                        'topic': item.topic,
                        'revision': item.revision,
                        'channel': item.channel,
                        'platform': item.platform,
                        'architecture': item.architecture,
                      },
                  ],
                })
                .timeout(const Duration(seconds: 10));
          },
        );
        sync = nextSync;
        if (!active) {
          await closeResources();
          return;
        }
        await nextSync.start();
        await channel.invokeMethod<void>('started');
        return;
      } catch (_) {
        await closeResources();
        if (!active) return;
        await channel.invokeMethod<void>('waiting').catchError((Object _) {});
        await Future<void>.delayed(Duration(seconds: delaySeconds));
        delaySeconds = (delaySeconds * 2).clamp(1, 60);
      }
    }
  } catch (_) {
    active = false;
    await closeResources();
    await channel.invokeMethod<void>('failed').catchError((Object _) {});
  }
}
