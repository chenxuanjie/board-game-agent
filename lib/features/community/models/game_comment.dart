/// Public comment DTO. The service, rather than a client-supplied NAS UID,
/// establishes authorship. Author IDs are application-specific pseudonyms.
final class CommentOperation {
  const CommentOperation({
    required this.id,
    required this.uid,
    required this.game,
    required this.at,
    this.author = '',
    this.text = '',
    this.root,
    this.replyTo,
    this.rating,
  });
  final String id, uid, game, author, text;
  final DateTime at;
  final String? root, replyTo;
  final int? rating;
  static final idPattern = RegExp(r'^c[0-9a-f]{32}$');
  static final gamePattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,127}$');
  factory CommentOperation.fromJson(Map<String, dynamic> r) => CommentOperation(
    id: r['id'] as String,
    uid: r['author_id'] as String,
    game: r['game_slug'] as String,
    at: DateTime.parse(r['created_at'] as String),
    author: r['author'] as String,
    text: r['text'] as String,
    root: r['root_id'] as String?,
    replyTo: r['parent_id'] as String?,
    rating: r['rating'] as int?,
  );
}

final class GameComment {
  const GameComment({
    required this.operation,
    required this.deleted,
    required this.likes,
    required this.likedByMe,
    required this.pending,
  });
  final CommentOperation operation;
  final bool deleted, likedByMe, pending;
  final int likes;
  String get id => operation.id;
}

final class CommentProjection {
  CommentProjection(Iterable<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final operation = CommentOperation.fromJson(row);
      comments[operation.id] = operation;
      _rows[operation.id] = row;
      if (row['deleted'] == true) deleted.add(operation.id);
    }
  }
  final Map<String, CommentOperation> comments = {};
  final Map<String, Map<String, dynamic>> _rows = {};
  final Set<String> deleted = {};
  List<GameComment> forGame(
    String slug,
    Set<String> pending, {
    bool latest = false,
  }) {
    final list = [
      for (final op in comments.values.where((c) => c.game == slug))
        GameComment(
          operation: op,
          deleted: deleted.contains(op.id),
          likes: _rows[op.id]!['likes'] as int? ?? 0,
          likedByMe: _rows[op.id]!['liked_by_me'] == true,
          pending: pending.contains(op.id),
        ),
    ];
    list.removeWhere(
      (c) =>
          c.deleted &&
          !list.any(
            (r) =>
                !r.deleted &&
                (r.operation.root == c.id || r.operation.replyTo == c.id),
          ),
    );
    list.sort((a, b) {
      final likes = latest ? 0 : b.likes.compareTo(a.likes);
      return likes != 0 ? likes : b.operation.at.compareTo(a.operation.at);
    });
    return list;
  }
}
