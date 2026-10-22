import 'dart:typed_data';

Future<Uint8List?> readBrowserAsset(String path) async => null;
Future<void> writeBrowserAsset(String path, Uint8List bytes) async =>
    throw UnsupportedError('Browser cache is only available on Web');
