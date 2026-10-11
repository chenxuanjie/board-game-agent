import 'dart:async';
import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:board_game_agent/features/games/models/game_vote_record.dart';
import 'package:board_game_agent/features/identity/services/account_public_reactions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/account_sync_fixture.dart';
import 'support/account_public_fixture.dart';

void _favorite(SyncDeviceFixture device, String slug) {
  device.entities['favorite|$slug'] = {
    'gameSlug': slug,
    'createdAt': '2026-10-08T01:00:00Z',
  };
}

void _vote(SyncDeviceFixture device, String slug) {
  device.entities['vote|$slug'] = {
    'slug': slug,
    'campaign': GameVoteBallot.campaign,
  };
}

Future<void> _publish(
  AccountPublicReactions remote,
  SyncDeviceFixture device,
) async {
  await device.local.capture();
  await remote.synchronize(device.local);
}

void main() {
  test(
    'simultaneous accounts read after their writes and each sees two likes',
    () async {
      final hub = PublicFixtureHub();
      final a = SyncDeviceFixture(), b = SyncDeviceFixture(scope: 'b');
      await a.start();
      await b.start();
      _favorite(a, 'carcassonne_3');
      _favorite(b, 'carcassonne_3');
      final bothWritten = Completer<void>();
      var writes = 0;
      Future<void> barrier() async {
        if (++writes == 2) bothWritten.complete();
        await bothWritten.future;
      }

      final ra = AccountPublicReactions(
        _HookPublicFiles(hub, 101)..afterWrite = barrier,
      );
      final rb = AccountPublicReactions(
        _HookPublicFiles(hub, 102)..afterWrite = barrier,
      );
      await Future.wait([_publish(ra, a), _publish(rb, b)]);
      expect(ra.counts(GameVoteBallot.favoritesNamespace)['carcassonne_3'], 1);
      expect(rb.counts(GameVoteBallot.favoritesNamespace)['carcassonne_3'], 1);
      expect(hub.writes, 2);
      expect(ra.submissionConfirmed, isTrue);
      expect(rb.submissionConfirmed, isTrue);
    },
  );

  test(
    'cancellation during upload publishes a tombstone before completing',
    () async {
      final hub = PublicFixtureHub();
      final a = SyncDeviceFixture();
      await a.start();
      _favorite(a, 'carcassonne_3');
      final entered = Completer<void>(), release = Completer<void>();
      final files = _HookPublicFiles(hub, 101)
        ..afterWrite = () async {
          if (!entered.isCompleted) {
            entered.complete();
            await release.future;
          }
        };
      final remote = AccountPublicReactions(files);
      final task = _publish(remote, a);
      await entered.future;
      a.entities.clear();
      await a.local.capture();
      release.complete();
      await task;
      expect(a.entities, isEmpty);
      expect(hub.writes, 2);
      expect(
        jsonDecode(
          hub.objects.values.single.text,
        )['operations'].single['operation'],
        'delete',
      );
      expect(remote.confirmedFingerprint, a.local.publicFingerprint);
    },
  );

  test(
    'confirmed upload with failed totals refresh retries without another upload',
    () async {
      final hub = PublicFixtureHub();
      final a = SyncDeviceFixture();
      await a.start();
      _favorite(a, 'carcassonne_3');
      final files = _HookPublicFiles(hub, 101);
      files.afterWrite = () async => files.failRoot = true;
      final remote = AccountPublicReactions(files);
      await expectLater(
        _publish(remote, a),
        throwsA(isA<PrivateFileException>()),
      );
      expect(remote.submissionConfirmed, isTrue);
      expect(hub.writes, 1);
      files.failRoot = false;
      await _publish(remote, a);
      expect(remote.error, isNull);
      expect(hub.writes, 1);
    },
  );

  test(
    'lost upload response recovers the remote version without counting twice',
    () async {
      final hub = PublicFixtureHub();
      final a = SyncDeviceFixture();
      await a.start();
      _favorite(a, 'carcassonne_3');
      final files = _HookPublicFiles(hub, 101)
        ..afterWrite = () async {
          throw const PrivateFileException(PrivateFileFailure.network);
        };
      final remote = AccountPublicReactions(files);
      await expectLater(
        _publish(remote, a),
        throwsA(isA<PrivateFileException>()),
      );
      expect(remote.submissionConfirmed, isFalse);
      files.afterWrite = null;
      await _publish(remote, a);
      expect(remote.submissionConfirmed, isTrue);
      expect(hub.writes, 1);
    },
  );

  test(
    'upload readback mismatch cannot confirm or replace cached totals',
    () async {
      final hub = PublicFixtureHub();
      final a = SyncDeviceFixture();
      await a.start();
      _favorite(a, 'carcassonne_3');
      final files = _HookPublicFiles(hub, 101)
        ..afterWrite = () async {
          final path = hub.objects.keys.single;
          hub.objects[path] = (owner: 101, text: '{}');
        };
      final remote = AccountPublicReactions(files);
      await expectLater(_publish(remote, a), throwsA(isA<Exception>()));
      expect(remote.submissionConfirmed, isFalse);
      expect(remote.counts(GameVoteBallot.favoritesNamespace), isEmpty);
      expect(a.entities, contains('favorite|carcassonne_3'));
    },
  );
  test(
    'administrator-provisioned folders count their UID namespaces separately',
    () async {
      final hub = PublicFixtureHub()
        ..directoryOwners.addAll({'u101': 900, 'u102': 900, 'u103': 900});
      final a = SyncDeviceFixture(),
          b = SyncDeviceFixture(scope: 'b'),
          observer = SyncDeviceFixture(scope: 'observer');
      for (final device in [a, b, observer]) {
        await device.start();
      }
      _vote(a, 'cabo');
      _vote(b, 'cabo');
      await _publish(AccountPublicReactions(MemoryPublicFiles(hub, 101)), a);
      await _publish(AccountPublicReactions(MemoryPublicFiles(hub, 102)), b);
      final remote = AccountPublicReactions(MemoryPublicFiles(hub, 103));
      await _publish(remote, observer);
      expect(remote.counts(GameVoteBallot.campaign), {'cabo': 2});
    },
  );
  test(
    'two devices of the same UID count once; another account counts separately',
    () async {
      final hub = PublicFixtureHub();
      final a = SyncDeviceFixture(),
          a2 = SyncDeviceFixture(),
          b = SyncDeviceFixture(scope: 'account-b'),
          observer = SyncDeviceFixture(scope: 'observer');
      for (final d in [a, a2, b, observer]) {
        await d.start();
      }
      final ra = AccountPublicReactions(MemoryPublicFiles(hub, 101));
      final ra2 = AccountPublicReactions(MemoryPublicFiles(hub, 101));
      final rb = AccountPublicReactions(MemoryPublicFiles(hub, 102));
      final ro = AccountPublicReactions(MemoryPublicFiles(hub, 103));
      _favorite(a, 'cabo');
      _vote(a, 'cabo');
      await _publish(ra, a);
      await _publish(ra2, a2);
      expect(a2.entities.keys, containsAll(['favorite|cabo', 'vote|cabo']));
      await _publish(ro, observer);
      expect(ro.counts(GameVoteBallot.campaign), {'cabo': 1});
      expect(ro.counts(GameVoteBallot.favoritesNamespace), {'cabo': 1});
      _favorite(b, 'cabo');
      _vote(b, 'cabo');
      await _publish(rb, b);
      await _publish(ro, observer);
      expect(ro.counts(GameVoteBallot.campaign), {'cabo': 2});
      expect(ro.counts(GameVoteBallot.favoritesNamespace), {'cabo': 2});
      await _publish(ra, a);
      expect(ra.counts(GameVoteBallot.campaign), {
        'cabo': 1,
      }); // own UID excluded
    },
  );

  test(
    'two account votes persist remotely and cancelling one leaves the other',
    () async {
      final hub = PublicFixtureHub();
      final a = SyncDeviceFixture(), b = SyncDeviceFixture(scope: 'account-b');
      await a.start();
      await b.start();
      final ra = AccountPublicReactions(MemoryPublicFiles(hub, 101));
      final rb = AccountPublicReactions(MemoryPublicFiles(hub, 102));
      _vote(a, 'cabo');
      _favorite(a, 'cabo');
      _vote(b, 'cabo');
      _favorite(b, 'cabo');
      await _publish(ra, a);
      await _publish(rb, b);
      final viewer = SyncDeviceFixture(scope: 'viewer');
      await viewer.start();
      final totals = AccountPublicReactions(MemoryPublicFiles(hub, 103));
      await _publish(totals, viewer);
      expect(totals.counts(GameVoteBallot.campaign), {'cabo': 2});
      expect(totals.counts(GameVoteBallot.favoritesNamespace), {'cabo': 2});
      // Re-enter the account using a fresh adapter/device and recover its vote.
      final restored = SyncDeviceFixture(scope: 'account-b');
      await restored.start();
      final restoredRemote = AccountPublicReactions(
        MemoryPublicFiles(hub, 102),
      );
      await _publish(restoredRemote, restored);
      expect(
        restored.entities.keys,
        containsAll(['vote|cabo', 'favorite|cabo']),
      );
      await _publish(totals, viewer);
      expect(totals.counts(GameVoteBallot.campaign), {'cabo': 2});
      restored.entities.clear();
      await _publish(restoredRemote, restored);
      await _publish(totals, viewer);
      expect(totals.counts(GameVoteBallot.campaign), {'cabo': 1});
      expect(totals.counts(GameVoteBallot.favoritesNamespace), {'cabo': 1});
      expect(hub.objects.keys.any((path) => path.startsWith('u101/')), isTrue);
    },
  );
  test(
    'cancellation tombstones defeat stale devices and survive a new device',
    () async {
      final hub = PublicFixtureHub();
      final a = SyncDeviceFixture(),
          a2 = SyncDeviceFixture(),
          fresh = SyncDeviceFixture();
      for (final d in [a, a2, fresh]) {
        await d.start();
      }
      final ra = AccountPublicReactions(MemoryPublicFiles(hub, 101)),
          ra2 = AccountPublicReactions(MemoryPublicFiles(hub, 101));
      _vote(a, 'cabo');
      _favorite(a, 'cabo');
      await _publish(ra, a);
      await _publish(ra2, a2);
      a2.entities.remove('favorite|cabo');
      a2.entities.remove('vote|cabo');
      await _publish(ra2, a2);
      await _publish(ra, a); // old device still has selection before merge
      expect(a.entities, isEmpty);
      await _publish(
        AccountPublicReactions(MemoryPublicFiles(hub, 101)),
        fresh,
      );
      expect(fresh.entities, isEmpty);
      expect(fresh.local.publicReactions.length, 2);
      expect(
        hub.objects.values.map((v) => v.text).join(),
        isNot(contains('password')),
      );
    },
  );

  test(
    'public heads do not skip preceding private conversation operations',
    () async {
      final hub = PublicFixtureHub();
      final private = MemoryPrivateFiles();
      final a = SyncDeviceFixture(), fresh = SyncDeviceFixture();
      await a.start();
      await fresh.start();
      a.entities['conversation|chat'] = {
        'id': 'chat',
        'messages': ['private text'],
      };
      await a.local.capture();
      _vote(a, 'cabo');
      await _publish(AccountPublicReactions(MemoryPublicFiles(hub, 101)), a);
      await _publish(
        AccountPublicReactions(MemoryPublicFiles(hub, 101)),
        fresh,
      );
      expect((await fresh.local.loadCheckpoint()).pullCursor.toJson(), isEmpty);
      expect(
        jsonEncode(hub.objects.values.map((v) => v.text).toList()),
        isNot(contains('private text')),
      );
      await a.sync(private);
      await fresh.sync(private);
      expect(fresh.entities['conversation|chat']?['messages'], [
        'private text',
      ]);
      expect(fresh.entities.keys, contains('vote|cabo'));
    },
  );

  test('unchanged public snapshot does not upload again', () async {
    final hub = PublicFixtureHub();
    final a = SyncDeviceFixture();
    await a.start();
    final remote = AccountPublicReactions(MemoryPublicFiles(hub, 101));
    _vote(a, 'cabo');
    await _publish(remote, a);
    final writes = hub.writes;
    await _publish(remote, a);
    expect(hub.writes, writes);
  });

  for (final failure in [
    PrivateFileFailure.denied,
    PrivateFileFailure.network,
    PrivateFileFailure.session,
    PrivateFileFailure.missing,
  ]) {
    test(
      '$failure preserves cached counts and durable local choices',
      () async {
        final hub = PublicFixtureHub();
        final a = SyncDeviceFixture(),
            b = SyncDeviceFixture(scope: 'account-b');
        await a.start();
        await b.start();
        final remote = AccountPublicReactions(MemoryPublicFiles(hub, 102));
        _vote(a, 'cabo');
        await _publish(AccountPublicReactions(MemoryPublicFiles(hub, 101)), a);
        await _publish(remote, b);
        hub.failure = failure;
        _vote(b, 'splendor');
        await b.local.capture();
        await expectLater(
          remote.synchronize(b.local),
          throwsA(isA<PrivateFileException>()),
        );
        expect(remote.counts(GameVoteBallot.campaign), {'cabo': 1});
        expect(b.entities.keys, contains('vote|splendor'));
        expect(remote.error, isNotNull);
      },
    );
  }

  test(
    'forged owner and malformed snapshots preserve previous complete totals',
    () async {
      final hub = PublicFixtureHub();
      final a = SyncDeviceFixture(), b = SyncDeviceFixture(scope: 'b');
      await a.start();
      await b.start();
      _vote(a, 'cabo');
      await _publish(AccountPublicReactions(MemoryPublicFiles(hub, 101)), a);
      final remote = AccountPublicReactions(MemoryPublicFiles(hub, 102));
      await _publish(remote, b);
      final path = hub.objects.keys.first;
      final valid = hub.objects[path]!;
      hub.objects[path] = (owner: 999, text: valid.text);
      await expectLater(remote.synchronize(b.local), throwsFormatException);
      expect(remote.counts(GameVoteBallot.campaign), {'cabo': 1});
      hub.objects[path] = (owner: 101, text: '{');
      await expectLater(remote.synchronize(b.local), throwsFormatException);
      expect(remote.counts(GameVoteBallot.campaign), {'cabo': 1});
    },
  );

  test('cancelled late read cannot publish or replace totals', () async {
    final hub = PublicFixtureHub();
    final a = SyncDeviceFixture(), b = SyncDeviceFixture(scope: 'b');
    await a.start();
    await b.start();
    _vote(a, 'cabo');
    await _publish(AccountPublicReactions(MemoryPublicFiles(hub, 101)), a);
    final remote = AccountPublicReactions(MemoryPublicFiles(hub, 102));
    hub.readGate = Completer<void>();
    final pending = remote.synchronize(b.local);
    final expectation = expectLater(
      pending,
      throwsA(isA<PrivateFileException>()),
    );
    await Future<void>.delayed(Duration.zero);
    final writes = hub.writes;
    remote.cancel();
    hub.readGate!.complete();
    await expectation;
    expect(hub.writes, writes);
    expect(remote.counts(GameVoteBallot.campaign), isEmpty);
  });
}

class _HookPublicFiles extends MemoryPublicFiles {
  _HookPublicFiles(super.hub, super.uid);
  Future<void> Function()? afterWrite;
  bool failRoot = false;
  @override
  Future<List<AccountPublicEntry>> entries(String relativePath) {
    if (relativePath.isEmpty && failRoot) {
      throw const PrivateFileException(PrivateFileFailure.network);
    }
    return super.entries(relativePath);
  }

  @override
  Future<void> replaceOwn(String relativePath, String content) async {
    await super.replaceOwn(relativePath, content);
    await afterWrite?.call();
  }
}
