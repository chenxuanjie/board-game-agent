import 'dart:convert';

/// One installation's ballot; uploading it again never creates extra votes.
class GameVoteBallot {
  GameVoteBallot({
    required this.deviceId,
    required Iterable<String> games,
    this.namespace = campaign,
  }) : games = Set.unmodifiable(games);

  static const campaign = 'national-day-2026';
  static const favoritesNamespace = 'game-favorites-v1';
  static final namespacePattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');
  static final devicePattern = RegExp(r'^[a-f0-9]{32}$');
  static final slugPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,119}$');
  final String deviceId;
  final String namespace;
  final Set<String> games;

  String encode() => jsonEncode({
    'version': 1,
    'campaign': namespace,
    'deviceId': deviceId,
    'games': games.toList()..sort(),
  });

  factory GameVoteBallot.decode(String text, {String namespace = campaign}) {
    if (text.length > (namespace == favoritesNamespace ? 512 : 64) * 1024) {
      throw const FormatException('Ballot too large');
    }
    final map = jsonDecode(text) as Map<String, dynamic>;
    final id = map['deviceId'];
    final games = map['games'];
    if (map['version'] != 1 ||
        map['campaign'] != namespace ||
        !namespacePattern.hasMatch(namespace) ||
        id is! String ||
        !devicePattern.hasMatch(id) ||
        games is! List ||
        games.length > (namespace == favoritesNamespace ? 2048 : 256) ||
        games.any((slug) => slug is! String || !slugPattern.hasMatch(slug))) {
      throw const FormatException('Invalid vote ballot');
    }
    return GameVoteBallot(
      deviceId: id,
      games: games.cast<String>(),
      namespace: namespace,
    );
  }
}

/// Cloud counts exclude this installation, so offline changes apply immediately.
class GameVoteCache {
  GameVoteCache({
    required this.ballot,
    this.remoteCounts = const {},
    this.lastScope,
  });
  final GameVoteBallot ballot;
  final Map<String, Map<String, int>> remoteCounts;
  final String? lastScope;

  String encode() => jsonEncode({
    'version': 1,
    'ballot': jsonDecode(ballot.encode()),
    'remoteCounts': remoteCounts,
    if (lastScope != null) 'lastScope': lastScope,
  });

  factory GameVoteCache.decode(
    String text, {
    String namespace = GameVoteBallot.campaign,
  }) {
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
      ballot: GameVoteBallot.decode(
        jsonEncode(map['ballot']),
        namespace: namespace,
      ),
      remoteCounts: Map.unmodifiable(counts),
      lastScope: map['lastScope'] as String?,
    );
  }
}
