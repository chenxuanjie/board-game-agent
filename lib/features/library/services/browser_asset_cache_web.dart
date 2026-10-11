import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

// Store response bodies only. Never persist Authorization headers or NAS URLs.
const _cacheName = 'board-game-library-v1';
String _key(String path) =>
    '${web.window.location.origin}/__library_cache__/${Uri.encodeComponent(path)}';

Future<Uint8List?> readBrowserAsset(String path) async {
  final cache = await web.window.caches.open(_cacheName).toDart;
  final response = await cache.match(_key(path).toJS).toDart;
  if (response == null) return null;
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

Future<void> writeBrowserAsset(String path, Uint8List bytes) async {
  final cache = await web.window.caches.open(_cacheName).toDart;
  await cache.put(_key(path).toJS, web.Response(bytes.toJS)).toDart;
}
