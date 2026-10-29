/// A durable invalidation watermark, never a download URL or account record.
final class PublicPublication {
  const PublicPublication({
    required this.id,
    required this.topic,
    required this.revision,
    this.channel = '',
    this.platform = '',
    this.architecture = '',
  });

  final String id, topic, channel, platform, architecture;
  final int revision;

  factory PublicPublication.fromRow(Map<String, dynamic> row) {
    final topic = row['topic'], revision = row['revision'];
    if (row['app_id'] != 'board_game_agent' ||
        row['id'] is! String ||
        !const {'catalog', 'release'}.contains(topic) ||
        revision is! int ||
        revision < 0 ||
        row['channel'] is! String ||
        row['platform'] is! String ||
        row['architecture'] is! String) {
      throw const FormatException('Invalid public publication');
    }
    return PublicPublication(
      id: row['id'] as String,
      topic: topic as String,
      revision: revision,
      channel: row['channel'] as String,
      platform: row['platform'] as String,
      architecture: row['architecture'] as String,
    );
  }
}
