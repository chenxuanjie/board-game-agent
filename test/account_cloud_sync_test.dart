import 'dart:convert';
import 'package:app_identity/app_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_sync/webdav_sync.dart';
import 'support/account_sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'offline outbox survives restart and distinct device changes converge',
    () async {
      final files = MemoryPrivateFiles()..failure = PrivateFileFailure.network;
      final a = SyncDeviceFixture(), b = SyncDeviceFixture();
      await a.start();
      await b.start();
      a.entities['favorite|catan'] = {'gameSlug': 'catan'};
      expect((await a.sync(files)).failed, isTrue);
      final id = a.local.deviceId;
      await a.start();
      expect(a.local.deviceId, id);
      b.entities['favorite|splendor'] = {'gameSlug': 'splendor'};
      files.failure = null;
      expect((await b.sync(files)).completed, isTrue);
      expect((await a.sync(files)).completed, isTrue);
      expect((await b.sync(files)).completed, isTrue);
      expect(a.entities.keys.toSet(), {'favorite|catan', 'favorite|splendor'});
      expect(b.entities, a.entities);
      final count = files.objects.length;
      expect((await a.sync(files)).uploaded, 0);
      expect(files.objects.length, count);
    },
  );
  test(
    'recent views keep the newest visit despite concurrent logical clocks',
    () async {
      final files = MemoryPrivateFiles(),
          a = SyncDeviceFixture(),
          b = SyncDeviceFixture();
      await a.start();
      await b.start();
      a.entities['recent|catan'] = {
        'gameSlug': 'catan',
        'viewedAt': '2026-10-05T00:00:00Z',
      };
      b.entities['recent|catan'] = {
        'gameSlug': 'catan',
        'viewedAt': '2026-10-04T00:00:00Z',
      };
      b.entities['nickname|profile'] = {'value': 'Other change'};
      await a.sync(files);
      await b.sync(files);
      await a.sync(files);
      expect(a.entities['recent|catan']?['viewedAt'], '2026-10-05T00:00:00Z');
      expect(b.entities['recent|catan'], a.entities['recent|catan']);
    },
  );
  test('delete tombstone prevents resurrection on a fresh device', () async {
    final files = MemoryPrivateFiles(),
        a = SyncDeviceFixture(),
        b = SyncDeviceFixture();
    await a.start();
    await b.start();
    a.entities['favorite|catan'] = {'gameSlug': 'catan'};
    await a.sync(files);
    await b.sync(files);
    b.entities.clear();
    expect((await b.sync(files)).completed, isTrue);
    await a.sync(files);
    final c = SyncDeviceFixture();
    await c.start();
    await c.sync(files);
    expect(a.entities, isEmpty);
    expect(c.entities, isEmpty);
  });
  test(
    'concurrent AI edits retain a stable conflict copy and converge',
    () async {
      final files = MemoryPrivateFiles(),
          a = SyncDeviceFixture(),
          b = SyncDeviceFixture();
      await a.start();
      await b.start();
      a.entities['conversation|chat'] = {
        'id': 'chat',
        'title': 'Rules',
        'messages': ['base'],
      };
      await a.sync(files);
      await b.sync(files);
      a.entities['conversation|chat']!['messages'] = ['device A'];
      b.entities['conversation|chat']!['messages'] = ['device B'];
      await a.sync(files);
      await b.sync(files);
      await a.sync(files);
      await b.sync(files);
      expect(a.entities.length, 2);
      expect(b.entities, a.entities);
      expect(
        a.entities.values.map((e) => e['messages']).toList(),
        containsAll([
          ['device A'],
          ['device B'],
        ]),
      );
      final count = files.objects.length;
      await a.sync(files);
      await b.sync(files);
      expect(files.objects.length, count);
    },
  );
  test(
    'failed projection replays durable intent while preserving subsequent edits',
    () async {
      final files = MemoryPrivateFiles(),
          a = SyncDeviceFixture(),
          b = SyncDeviceFixture();
      await a.start();
      await b.start();
      a.entities['nickname|profile'] = {'value': 'cloud name'};
      await a.sync(files);
      b.failProjection = true;
      expect((await b.sync(files)).failed, isTrue);
      b.entities['favorite|catan'] = {'gameSlug': 'catan'};
      b.failProjection = false;
      await b.start();
      expect((await b.sync(files)).completed, isTrue);
      expect(b.entities['nickname|profile'], {'value': 'cloud name'});
      expect(b.entities.containsKey('favorite|catan'), isTrue);
      await a.sync(files);
      expect(a.entities, b.entities);
    },
  );
  test(
    'corruption, missing operation and wrong account never silently apply',
    () async {
      final files = MemoryPrivateFiles(), a = SyncDeviceFixture();
      await a.start();
      a.entities['favorite|catan'] = {'gameSlug': 'catan'};
      await a.sync(files);
      final original = files.objects.values.single;
      final bad = jsonDecode(original) as Map<String, dynamic>;
      bad['payload'] = {'gameSlug': 'changed'};
      files.objects[files.objects.keys.single] = jsonEncode(bad);
      final b = SyncDeviceFixture();
      await b.start();
      expect((await b.sync(files)).failed, isTrue);
      expect(b.entities, isEmpty);
      files.objects[files.objects.keys.single] = original;
      final other = SyncDeviceFixture(scope: 'account-b');
      await other.start();
      expect((await other.sync(files)).failed, isTrue);
      expect(other.entities, isEmpty);
      a.entities['favorite|another'] = {'gameSlug': 'another'};
      await a.sync(files);
      files.objects.removeWhere(
        (key, value) => key.endsWith('0000000000000001.json'),
      );
      expect((await b.sync(files)).failed, isTrue);
      expect(b.entities, isEmpty);
    },
  );
  test(
    'denied private home is not retried or redirected to shared resources',
    () async {
      final files = MemoryPrivateFiles()..failure = PrivateFileFailure.denied;
      final a = SyncDeviceFixture();
      await a.start();
      a.entities['favorite|local'] = {'gameSlug': 'local'};
      final result = await a.sync(files);
      expect(result.failed, isTrue);
      expect(files.calls, 1);
      expect(a.entities.containsKey('favorite|local'), isTrue);
    },
  );
  test(
    'default journal persists pending operations in the account namespace',
    () async {
      final a = SyncDeviceFixture();
      await a.start();
      a.entities['preference|voice_reply_enabled'] = {'value': true};
      await a.local.capture();
      final restored = SyncDeviceFixture()..journal = a.journal;
      await restored.start();
      final operations = await restored.local.pendingOperations(
        afterSequence: 0,
      );
      expect(operations.single.entityType, 'preference');
      expect(operations.single.payload, {'value': true});
      expect(
        SyncOperation.fromJson(operations.single.toJson()).payloadHash,
        operations.single.payloadHash,
      );
    },
  );
}
