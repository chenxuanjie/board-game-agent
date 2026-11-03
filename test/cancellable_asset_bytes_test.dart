import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:board_game_agent/features/library/services/cancellable_asset_bytes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cancelled blocked reads release their owned stream before returning',
    () async {
      final abort = Completer<void>(),
          cancelling = Completer<void>(),
          released = Completer<void>();
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelling.complete();
          return released.future;
        },
      );
      final read = readAssetBytes(
        stream.stream,
        abort: abort.future,
        maxBytes: 100,
      );
      var settled = false;
      final assertion = expectLater(
        read.whenComplete(() => settled = true),
        throwsA(isA<TimeoutException>()),
      );
      stream.add([1, 2]);
      await Future<void>.delayed(Duration.zero);
      abort.complete();
      await cancelling.future;
      expect(
        settled,
        isFalse,
      ); // caller must not confuse cancellation with cleanup
      released.complete();
      await assertion;
      await stream.close();
    },
  );

  test('hashing yields so cancellation stops a large cached input', () async {
    final abort = Completer<void>();
    final bytes = Uint8List(8 * 1024 * 1024);
    final digest = digestAssetBytes(bytes, abort: abort.future);
    final assertion = expectLater(digest, throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(Duration.zero);
    abort.complete();
    await assertion;
  });

  test('cancelled file reads can release their file immediately', () async {
    final directory = await Directory.systemTemp.createTemp(
      'asset-read-cancel-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cached.bin');
    await file.writeAsBytes(Uint8List(1024 * 1024));
    final abort = Completer<void>();
    final read = readAssetBytes(
      file.openRead(),
      abort: abort.future,
      maxBytes: 2 * 1024 * 1024,
    );
    final assertion = expectLater(read, throwsA(isA<TimeoutException>()));
    abort.complete();
    await assertion;
    await file.delete();
    expect(await file.exists(), isFalse);
  });

  test(
    'a cancelled cache write drains its current chunk and closes before staging cleanup',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'asset-write-cancel-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = File('${directory.path}/pending.knowledge');
      final writing = Completer<void>(),
          release = Completer<void>(),
          abort = Completer<void>();
      final file = _HeldFile(target, writing, release);
      var settled = false;
      final write = () async {
        try {
          await writeAssetBytes(
            file,
            Uint8List(1024 * 1024),
            abort: abort.future,
          );
        } finally {
          expect(file.handle!.closed, isTrue);
          if (await target.exists()) await target.delete();
          settled = true;
        }
      }();
      final assertion = expectLater(write, throwsA(isA<TimeoutException>()));
      await writing.future;
      abort.complete();
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      release.complete();
      await assertion;
      expect(file.handle!.writes, 1);
      expect(await directory.list().toList(), isEmpty);
    },
  );
}

class _HeldFile implements File {
  _HeldFile(this.file, this.writing, this.release);
  final File file;
  final Completer<void> writing, release;
  _HeldHandle? handle;
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      handle = _HeldHandle(await file.open(mode: mode), writing, release);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HeldHandle implements RandomAccessFile {
  _HeldHandle(this.file, this.writing, this.release);
  final RandomAccessFile file;
  final Completer<void> writing, release;
  bool closed = false;
  int writes = 0;
  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    writes++;
    await file.writeFrom(buffer, start, end);
    if (!writing.isCompleted) writing.complete();
    await release.future;
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    await file.flush();
    return this;
  }

  @override
  Future<void> close() async {
    await file.close();
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
