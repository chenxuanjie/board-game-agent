import 'dart:convert';

/// One installation's ballot; uploading it again never creates extra votes.
class GameVoteBallot {
  GameVoteBallot({required this.deviceId, required Iterable<String> games})
    : games = Set.unmodifiable(games);

  static const campaign = 'national-day-2026';
  static final devicePattern = RegExp(r'^[a-f0-9]{32}$');
  static final slugPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,119}$');
  final String deviceId;
  final Set<String> games;

  String encode() => jsonEncode({
    'version': 1,
    'campaign': campaign,
    'deviceId': deviceId,
    'games': games.toList()..sort(),
  });

  factory GameVoteBallot.decode(String text) {
    if (text.length > 64 * 1024) {
      throw const FormatException('Ballot too large');
    }
    final map = jsonDecode(text) as Map<String, dynamic>;
    final id = map['deviceId'];
    final games = map['games'];
    if (map['version'] != 1 ||
        map['campaign'] != campaign ||
        id is! String ||
        !devicePattern.hasMatch(id) ||
        games is! List ||
        games.length > 256 ||
        games.any((slug) => slug is! String || !slugPattern.hasMatch(slug))) {
      throw const FormatException('Invalid vote ballot');
    }
    return GameVoteBallot(deviceId: id, games: games.cast<String>());
  }
}

/// Cloud counts exclude this installation, so offline changes apply immediately.
class GameVoteCache {
  GameVoteCache({required this.ballot, this.remoteCounts = const {}});
  final GameVoteBallot ballot;
  final Map<String, Map<String, int>> remoteCounts;

  String encode() => jsonEncode({
    'version': 1,
    'ballot': jsonDecode(ballot.encode()),
    'remoteCounts': remoteCounts,
  });

  factory GameVoteCache.decode(String text) {
    final map = jsonDecode(text) as Map<String, dynamic>;
    if (map['version'] != 1) throw const FormatException('Unknown vote cache');
    final counts = <String, Map<String, int>>{};
    for (final entry in (map['remoteCounts'] as Map<String, dynamic>).entries) {
      final values = Map<String, int>.from(entry.value as Map);
      if (values.entries.any(
        (e) => !GameVoteBallot.slugPattern.hasMatch(e.key) || e.value < 0,
      )) {
        throw const FormatException('Invalid vote counts');
      }
      counts[entry.key] = Map.unmodifiable(values);
    }
    return GameVoteCache(
      ballot: GameVoteBallot.decode(jsonEncode(map['ballot'])),
      remoteCounts: Map.unmodifiable(counts),
    );
  }
}
