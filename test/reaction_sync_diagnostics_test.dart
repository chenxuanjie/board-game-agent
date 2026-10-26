import 'dart:async';

import 'package:board_game_agent/features/games/models/game_vote_record.dart';
import 'package:board_game_agent/features/games/services/game_vote_service.dart';
import 'package:board_game_agent/features/games/services/remote_game_vote_store.dart';
import 'package:board_game_agent/features/identity/services/reaction_sync_diagnostics.dart';
import 'package:board_game_agent/features/settings/services/preferences_service.dart';
import 'package:board_game_agent/ui/shared/reaction_sync_diagnostics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
