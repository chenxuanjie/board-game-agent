import 'package:board_game_agent/core/localization/app_language.dart';
import 'package:board_game_agent/features/library/models/asset_source_config.dart';
import 'package:board_game_agent/features/library/services/remote_asset_service.dart';
import 'package:board_game_agent/core/localization/app_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:board_game_agent/core/models/connectivity_status.dart';

void main() {
  test(
    'signed-out library rejects network, cache and bundled fallback',
    () async {
      var requests = 0;
      final service = RemoteAssetService(
        accessAllowed: () => false,
        client: MockClient((_) async {
          requests++;
          return http.Response('unexpected', 200);
        }),
      );
      const path = 'assets/games/cabo/docs/rulebook_en.md';
      expect(
        await service.ensureCached(
          sources: AssetSourceConfig.defaults,
          remotePath: path,
        ),
        isNull,
      );
      expect(
        await service.loadBytes(
          sources: AssetSourceConfig.defaults,
          remotePath: path,
        ),
        isNull,
      );
      expect(
        await service.fetchRemoteBytes(
          sources: AssetSourceConfig.defaults,
          remotePath: path,
        ),
        isNull,
      );
      expect(await service.cachedFileFor(path), isNull);
      expect(await service.cachedBytesFor(path), isNull);
      expect(await service.loadCachedOrBundledText(remotePath: path), isNull);
      expect(
        await service.hasRemoteChanged(
          sources: AssetSourceConfig.defaults,
          remotePath: path,
        ),
        isFalse,
      );
      final status = await service.checkAccess(
        AssetSourceConfig.defaults.first,
      );
      expect(status.state, ConnectivityState.failure);
      expect(status.message, '需要重新登录');
      await expectLater(
        service.listFilesRecursively(
          sources: AssetSourceConfig.defaults,
          remotePath: 'assets/games/cabo',
        ),
        throwsStateError,
      );
      expect(requests, 0);
    },
  );
  test('logout discards a late successful library response', () async {
    var allowed = true;
    final started = Completer<void>();
    final reply = Completer<http.Response>();
    final service = RemoteAssetService(
      accessAllowed: () => allowed,
      client: MockClient((_) {
        started.complete();
        return reply.future;
      }),
    );
    final read = service.fetchRemoteBytes(
      sources: [AssetSourceConfig.defaults.first],
      remotePath: 'assets/catalog.json',
    );
    await started.future;
    allowed = false;
    reply.complete(http.Response('{"games":[]}', 200));
    expect(await read, isNull);
  });
  test('empty resource paths are ignored without touching WebDAV', () async {
    final RemoteAssetService service = RemoteAssetService(
      client: _UnexpectedRequestClient(),
    );

    expect(
      await service.ensureCached(
        sources: AssetSourceConfig.defaults,
        remotePath: '',
      ),
      isNull,
    );
    expect(
      await service.fetchRemoteBytes(
        sources: AssetSourceConfig.defaults,
        remotePath: '',
      ),
      isNull,
    );
    expect(
      await service.loadBytes(
        sources: AssetSourceConfig.defaults,
        remotePath: '',
      ),
      isNull,
    );
    expect(await service.cachedFileFor(''), isNull);
    expect(
      await service.hasRemoteChanged(
        sources: AssetSourceConfig.defaults,
        remotePath: '',
      ),
      isFalse,
    );
  });

  test('docs/others paths are ignored without touching WebDAV', () async {
    final RemoteAssetService service = RemoteAssetService(
      client: _UnexpectedRequestClient(),
    );
    const String path =
        'assets/games/cabo/docs/others/raw/rulebook_extracted_en.txt';

    expect(
      await service.ensureCached(
        sources: AssetSourceConfig.defaults,
        remotePath: path,
      ),
      isNull,
    );
    expect(
      await service.fetchRemoteBytes(
        sources: AssetSourceConfig.defaults,
        remotePath: path,
      ),
      isNull,
    );
    expect(
      await service.loadBytes(
        sources: AssetSourceConfig.defaults,
        remotePath: path,
      ),
      isNull,
    );
    expect(await service.cachedFileFor(path), isNull);
    expect(
      await service.hasRemoteChanged(
        sources: AssetSourceConfig.defaults,
        remotePath: path,
      ),
      isFalse,
    );
  });

  test('missing document copy avoids exposing internal loading errors', () {
    final AppCopy copy = AppCopy(AppLanguage.zhHans);

    expect(copy.documentUnavailable('规则书'), '暂时找不到“规则书”，资料可能还在同步中，请稍后再试。');
    expect(copy.documentLoadFailed('规则书'), '“规则书”暂时无法读取，请稍后重试。');
    expect(copy.documentRenderFailed('规则书'), '“规则书”暂时无法打开，文件可能损坏或格式暂不支持。');
  });
}

class _UnexpectedRequestClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('Unexpected WebDAV request.');
  }
}
