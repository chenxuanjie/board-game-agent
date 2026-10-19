import 'dart:async';

import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/features/games/models/game_vote_record.dart';
import 'package:board_game_agent/features/games/services/game_vote_service.dart';
import 'package:board_game_agent/features/games/services/remote_game_vote_store.dart';
import 'package:board_game_agent/features/identity/services/account_public_reactions.dart';
import 'package:board_game_agent/features/identity/services/reaction_sync_diagnostics.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/shared/reaction_sync_diagnostics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/account_public_fixture.dart';
import 'support/account_sync_fixture.dart';

void main() {
  test(
    'diagnostics are bounded, redact failure bodies and reject old identity callbacks',
    () async {
      final log = ReactionSyncDiagnostics();
      addTearDown(log.dispose);
      final old = log.start('喜欢', show: true);
      for (var i = 0; i < 200; i++) {
        old.event('阶段 $i');
      }
      expect(log.events.length, 180);
      await expectLater(
        old.measure(
          'NAS 请求',
          () async =>
              throw StateError('password=secret https://nas/?_sid=secret'),
        ),
        throwsStateError,
      );
      expect(log.export(), isNot(contains('secret')));
      expect(log.export(), contains('StateError'));
      log.reset();
      old.finish(detail: 'old result');
      expect(log.events, isEmpty);
      expect(log.activeStages, isEmpty);
      expect(log.visible, isFalse);
    },
  );

  test(
    'verified native capability avoids duplicate readback and reports actual cancellation',
    () async {
      final hub = PublicFixtureHub(), device = SyncDeviceFixture();
      await device.start();
      final files = _VerifiedMemoryFiles(hub, 101);
      final remote = AccountPublicReactions(files);
      final log = ReactionSyncDiagnostics()..watch('cabo');
      addTearDown(log.dispose);
      device.entities['favorite|cabo'] = {
        'gameSlug': 'cabo',
        'createdAt': '2026-10-18T01:00:00Z',
      };
      await remote.publish(device.local, trace: log.start('publish'));
      expect(hub.reads.values.single, 1); // Adapter's own readback only.
      device.entities.clear();
      await remote.publish(device.local, trace: log.start('cancel'));
      expect(hub.reads.values.single, 3); // One fresh input plus one readback.
      expect(
        remote.confirmsSelection(GameVoteBallot.favoritesNamespace, []),
        isTrue,
      );
      expect(log.export(), contains('远端已核对状态'));
      expect(log.export(), contains('已取消（删除标记）'));
      expect(log.export(), contains('上传并读回核对'));
      await remote.refresh(device.local);
      expect(
        remote.observedRemoteCount(GameVoteBallot.favoritesNamespace, 'cabo'),
        0,
      );
    },
  );

  test(
    'manual refresh reaches coordinator while the previous model read is blocked',
    () async {
      final remote = _HeldCoordinator();
      final votes = GameVoteService(
        preferences: _MemoryPreferences(),
        remoteProvider: () => remote,
      );
      addTearDown(votes.dispose);
      final first = votes.sync();
      await remote.entered.future;
      final fresh = votes.sync(fresh: true);
      expect(remote.requests, 2);
      remote.release.complete();
      await Future.wait([first, fresh]);
      expect(remote.uploads, 0);
    },
  );

  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'native diagnostics remain usable at $width dp and large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final log = ReactionSyncDiagnostics();
        final trace = log.start('取消喜欢', show: true, detail: 'cabo');
        trace.event('写入本机收藏', status: ReactionTraceStatus.running);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: ReactionSyncDiagnosticsHost(
                diagnostics: log,
                child: child!,
              ),
            ),
            home: const Scaffold(body: Text('排行榜')),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 2));
        expect(find.textContaining('已等待'), findsWidgets);
        trace.finish(detail: '本机已保存');
        await tester.pump();
        await tester.tap(find.byTooltip('收起过程'));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('reaction-sync-events')),
          findsNothing,
        );
        await tester.tap(find.byTooltip('展开过程'));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('reaction-sync-events')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('关闭过程窗口'));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('reaction-sync-diagnostics')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        log.dispose();
      },
    );
  }
}

class _VerifiedMemoryFiles extends MemoryPublicFiles
    implements VerifiedAccountPublicFiles {
  _VerifiedMemoryFiles(super.hub, super.uid);
  @override
  Future<void> replaceOwn(String path, String text) async {
    await super.replaceOwn(path, text);
    if (await read(path) != text) throw StateError('readback mismatch');
  }
}

class _MemoryPreferences extends PreferencesService {
  String? data;
  @override
  Future<String?> loadGameVoteCache() async => data;
  @override
  Future<void> saveGameVoteCache(String value) async {
    data = value;
  }
}

class _HeldCoordinator implements CoordinatedGameVoteStore {
  final entered = Completer<void>(), release = Completer<void>();
  int requests = 0, uploads = 0;
  @override
  String get scope => 'account-public-v1.test';
  @override
  bool get enabled => true;
  @override
  Future<void> synchronize() async {
    requests++;
    if (!entered.isCompleted) entered.complete();
    await release.future;
  }

  @override
  Future<void> upload(GameVoteBallot ballot) async {
    uploads++;
  }

  @override
  Future<List<GameVoteBallot>> readBallots() async => [];
  @override
  void close() {}
}
