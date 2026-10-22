import 'dart:convert';

enum CommentAction { publish, delete, like }

/// Immutable authored event. The surrounding DSM-owned file establishes UID.
final class CommentOperation {
  const CommentOperation({
    required this.id,
    required this.uid,
    required this.game,
    required this.action,
    required this.revision,
    required this.at,
    this.author = '',
    this.text = '',
    this.root,
    this.replyTo,
    this.target,
    this.rating,
    this.liked = false,
  });
  final String id, game, author, text;
  final int uid, revision;
  final DateTime at;
  final CommentAction action;
  final String? root, replyTo, target;
  final int? rating;
  final bool liked;

  Map<String, Object?> toJson() => {
    'id': id,
    'uid': uid,
    'game': game,
    'action': action.name,
    'revision': revision,
    'at': at.toUtc().toIso8601String(),
    'author': author,
    'text': text,
    'root': root,
    'replyTo': replyTo,
    'target': target,
    'rating': rating,
    'liked': liked,
  };
  static final idPattern = RegExp(r'^c[0-9a-f]{32}$');
  static final gamePattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,127}$');
  factory CommentOperation.fromJson(Map<String, dynamic> data, int owner) {
    final op = CommentOperation(
      id: data['id'] as String,
      uid: data['uid'] as int,
      game: data['game'] as String,
      action: CommentAction.values.byName(data['action'] as String),
      revision: data['revision'] as int,
      at: DateTime.parse(data['at'] as String),
      author: data['author'] as String,
      text: data['text'] as String,
      root: data['root'] as String?,
      replyTo: data['replyTo'] as String?,
      target: data['target'] as String?,
      rating: data['rating'] as int?,
      liked: data['liked'] as bool,
    );
    if (op.uid != owner ||
        owner <= 0 ||
        !idPattern.hasMatch(op.id) ||
        !gamePattern.hasMatch(op.game) ||
        op.revision < 1 ||
        op.revision > 9007199254740991 ||
        op.author.length > 80 ||
        op.text.length > 1000 ||
        op.at.year < 2020 ||
        op.at.year > 2100 ||
        [
          op.root,
          op.replyTo,
          op.target,
        ].whereType<String>().any((v) => !idPattern.hasMatch(v)) ||
        (op.rating != null && (op.rating! < 1 || op.rating! > 10)) ||
        (op.action == CommentAction.publish &&
            (op.text.trim().isEmpty ||
                op.author.trim().isEmpty ||
                op.target != null ||
                (op.root != null && op.rating != null) ||
                (op.root == null) != (op.replyTo == null))) ||
        (op.action != CommentAction.publish &&
            (op.target == null ||
                op.text.isNotEmpty ||
                op.rating != null ||
                op.root != null ||
                op.replyTo != null))) {
      throw const FormatException('评论记录无效');
    }
    return op;
  }
  int compareTo(CommentOperation other) {
    final order = revision.compareTo(other.revision);
    return order != 0 ? order : id.compareTo(other.id);
  }

  bool sameAs(CommentOperation other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
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

/// Ratings count accounts, not comments. Deleting the current rated comment
/// clears the rating; an older comment never silently becomes effective again.
final class CommentProjection {
  CommentProjection(Iterable<CommentOperation> events, this.uid) {
    for (final op in events) {
      if (op.action == CommentAction.publish) comments[op.id] = op;
    }
    for (final op in events) {
      final target = comments[op.target];
      if (target == null || target.game != op.game) continue;
      if (op.action == CommentAction.delete && target.uid == op.uid) {
        deleted.add(target.id);
      } else if (op.action == CommentAction.like) {
        final key = '${op.uid}|${target.id}';
        if (_likes[key] == null || op.compareTo(_likes[key]!) > 0) {
          _likes[key] = op;
        }
      }
    }
  }
  final int uid;
  final Map<String, CommentOperation> comments = {};
  final Set<String> deleted = {};
  final Map<String, CommentOperation> _likes = {};

  List<GameComment> forGame(
    String slug,
    Set<String> pending, {
    bool latest = false,
  }) {
    final list = comments.values
        .where(
          (c) =>
              c.game == slug &&
              (c.root == null || comments[c.root]?.game == slug),
        )
        .map(
          (c) => GameComment(
            operation: c,
            deleted: deleted.contains(c.id),
            likes: _likes.values
                .where((v) => v.target == c.id && v.liked)
                .length,
            likedByMe: _likes['$uid|${c.id}']?.liked == true,
            pending: pending.contains(c.id),
          ),
        )
        .toList();
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
      if (!latest) {
        final likes = b.likes.compareTo(a.likes);
        if (likes != 0) return likes;
      }
      final date = b.operation.at.compareTo(a.operation.at);
      return date != 0 ? date : b.id.compareTo(a.id);
    });
    return list;
  }

  Map<int, int> ratings(String slug) {
    final heads = <int, CommentOperation>{};
    for (final c in comments.values.where(
      (c) => c.game == slug && c.rating != null,
    )) {
      if (heads[c.uid] == null || c.compareTo(heads[c.uid]!) > 0) {
        heads[c.uid] = c;
      }
    }
    return {
      for (final c in heads.values)
        if (!deleted.contains(c.id)) c.uid: c.rating!,
    };
  }
}
