import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _chunkSize = 64 * 1024;

Future<T> awaitAssetRead<T>(Future<T> operation, Future<void>? abort) =>
    abort == null
    ? operation
    : Future.any([
        operation,
        abort.then<T>((_) => throw TimeoutException('Asset read cancelled')),
      ]);

/// Cancel the owned subscription as well as stopping consumption. This also
/// works with a response stream that does not implement HTTP abort itself.
Future<Uint8List> readAssetBytes(
  Stream<List<int>> stream, {
  required Future<void> abort,
  required int maxBytes,
}) async {
  final bytes = BytesBuilder(copy: false);
  final result = Completer<Uint8List>();
  var finished = false;
  final subscription = stream.listen(
    (chunk) {
      if (result.isCompleted) return;
      if (bytes.length + chunk.length > maxBytes) {
        result.completeError(StateError('request_too_large'));
      } else {
        bytes.add(chunk);
      }
    },
    onError: (Object error, StackTrace stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    },
    onDone: () {
      finished = true;
      if (!result.isCompleted) result.complete(bytes.takeBytes());
    },
  );
  try {
    return await awaitAssetRead(result.future, abort);
  } finally {
    // A done stream has already released its subscription. On error or abort,
    // explicitly await cleanup instead of letting cancelOnError detach it.
    if (!finished) await subscription.cancel();
  }
}

/// Yield to the event loop between bounded chunks, so a stop tap can be
/// delivered during hashing instead of waiting for one large synchronous hash.
Future<String> digestAssetBytes(List<int> bytes, {Future<void>? abort}) async {
  Stream<List<int>> chunks() async* {
    for (var offset = 0; offset < bytes.length; offset += _chunkSize) {
      await awaitAssetRead(Future<void>.delayed(Duration.zero), abort);
      final end = offset + _chunkSize < bytes.length
          ? offset + _chunkSize
          : bytes.length;
      yield bytes is Uint8List
          ? Uint8List.sublistView(bytes, offset, end)
          : bytes.sublist(offset, end);
    }
  }

  return (await sha256.bind(chunks()).first).toString();
}

/// Never detach a write and race deletion against its open file handle.
/// Cancellation stops before the next chunk; the current OS write is drained
/// and the handle is closed before the caller removes its staging file.
Future<void> writeAssetBytes(
  File target,
  List<int> bytes, {
  required Future<void> abort,
}) async {
  var cancelled = false;
  abort.then((_) => cancelled = true);
  void guard() {
    if (cancelled) throw TimeoutException('Asset cache write cancelled');
  }

  await Future<void>.delayed(Duration.zero);
  guard();
  final file = await target.open(mode: FileMode.write);
  try {
    for (var offset = 0; offset < bytes.length; offset += _chunkSize) {
      guard();
      final end = offset + _chunkSize < bytes.length
          ? offset + _chunkSize
          : bytes.length;
      await file.writeFrom(bytes, offset, end);
    }
    guard();
    await file.flush();
    guard();
  } finally {
    await file.close();
  }
}
