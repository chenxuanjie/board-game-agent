import 'package:board_game_agent/features/games/models/game_metadata_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('play time keeps the full range and its maximum', () {
    expect(GameMetadataText.playTime('90-150 分钟'), '90–150 分钟');
    expect(GameMetadataText.playTime('约 45-60 分钟'), '45–60 分钟');
    expect(GameMetadataText.playTime('45-90 分钟 / 每幕'), '45–90 分钟/幕');
    expect(GameMetadataText.playTime('约 15 分钟/人'), '15 分钟/人');
    expect(GameMetadataText.playTime('About 45-60 minutes'), '45–60 min');
    expect(GameMetadataText.playTime(''), '—');
    expect(GameMetadataText.playTime('-'), '—');
  });

  test('player ranges preserve variants while using one dash style', () {
    expect(GameMetadataText.players('3-5 人'), '3–5 人');
    expect(GameMetadataText.players('4-11 人（含 2 人变体）'), '4–11 人（含 2 人变体）');
    expect(GameMetadataText.players('2 人 / 2v2'), '2 人 / 2v2');
    expect(GameMetadataText.players('-'), '—');
  });

  test('recommendation facts use compact labels without losing range ends', () {
    expect(GameMetadataText.cardPlayers('4-11 人（含 2 人变体）'), '4–11 人');
    expect(GameMetadataText.cardPlayers('2 人 / 2v2'), '2 人');
    expect(GameMetadataText.cardPlayers('3-5 players'), '3–5');
    expect(GameMetadataText.cardPlayTime('90-150 分钟'), '90–150');
    expect(GameMetadataText.cardPlayTime('约 15 分钟/人'), '15/人');
    expect(GameMetadataText.cardPlayTime('45-90 分钟 / 每幕'), '45–90/幕');
    expect(GameMetadataText.cardPlayTime('45-90 min per Act'), '45–90/Act');
  });
}
