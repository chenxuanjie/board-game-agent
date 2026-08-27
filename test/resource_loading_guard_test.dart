import 'package:board_game_agent/models/app_language.dart';
import 'package:board_game_agent/models/asset_source_config.dart';
import 'package:board_game_agent/services/remote_asset_service.dart';
import 'package:board_game_agent/ui/app_copy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
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
