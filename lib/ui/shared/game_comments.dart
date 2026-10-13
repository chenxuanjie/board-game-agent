import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_motion.dart';
import '../../features/community/models/game_comment.dart';
import '../../features/community/services/game_comments_service.dart';
import 'account_scope.dart';
import 'account_screen.dart';
import 'app_modals.dart';

/// Both platforms share comment state and actions; only entry/composition vary.
class GameCommentsPanel extends StatefulWidget {
  const GameCommentsPanel({
    super.key,
    required this.gameSlug,
    required this.gameTitle,
    this.preview = false,
    this.rootId,
    this.service,
    this.recentCommentId,
  });
  final String gameSlug, gameTitle;
  final bool preview;
  final String? rootId;
  final GameCommentsService? service;
  final String? recentCommentId;
  @override
  State<GameCommentsPanel> createState() => _GameCommentsPanelState();
}

class _GameCommentsPanelState extends State<GameCommentsPanel> {
  GameCommentsService? _service;
  bool _latest = false;
  int _limit = 20;
  String? _freshId;
  final Set<String> _liking = {};
  final Map<String, String> _likeErrors = {};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind(widget.service ?? AccountScope.maybeOf(context)?.comments);
  }

  @override
  void didUpdateWidget(covariant GameCommentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameSlug != widget.gameSlug ||
        oldWidget.rootId != widget.rootId) {
      _limit = 20;
      _freshId = null;
    }
    _bind(widget.service ?? AccountScope.maybeOf(context)?.comments);
    if (oldWidget.recentCommentId != widget.recentCommentId) {
      _freshId = widget.recentCommentId;
    }
  }

  void _bind(GameCommentsService? service) {
    if (identical(service, _service)) return;
    _service?.removeListener(_changed);
    _service = service;
    _freshId = null;
    _liking.clear();
    _likeErrors.clear();
    service?.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_service, service)) {
        unawaited(service?.synchronize());
      }
    });
  }

  void _changed() {
    final service = _service;
    if (service != null && !service.loading && service.error == null) {
      _likeErrors.removeWhere((id, _) => !service.likePending(id));
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service?.removeListener(_changed);
    super.dispose();
  }

  Future<void> _work(Future<void> Function() work) async {
    try {
      await work();
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure is StateError ? failure.message.toString() : '操作未完成，请重试',
            ),
          ),
        );
      }
    }
  }

  Future<void> _like(GameComment comment) async {
    if (_likeBusy(comment.id)) return;
    if (!_liking.add(comment.id)) return;
    final service = _service!;
    setState(() => _likeErrors.remove(comment.id));
    try {
      await service.toggleLike(comment);
      if (mounted &&
          identical(service, _service) &&
          (service.error != null || service.likePending(comment.id))) {
        _likeErrors[comment.id] = '点赞同步未完成，请重试';
      }
    } catch (_) {
      if (mounted && identical(service, _service)) {
        _likeErrors[comment.id] = '点赞未完成，请重试';
      }
    } finally {
      if (mounted && identical(service, _service)) {
        setState(() => _liking.remove(comment.id));
      }
    }
  }

  bool _likeBusy(String id) =>
      _liking.contains(id) ||
      _service?.loading == true && _service!.likePending(id);

  void _openReplies(GameComment comment) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameCommentsPage(
          gameSlug: widget.gameSlug,
          gameTitle: widget.gameTitle,
          rootId: comment.operation.root ?? comment.id,
          service: widget.service,
        ),
      ),
    );
  }

  Future<void> _compose([GameComment? reply]) async {
    final service = _service;
    if (service == null || !service.canWrite) return;
    await showAppBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: _CommentComposer(
            key: ValueKey('${service.scope}|${reply?.id ?? 'root'}'),
            service: service,
            game: widget.gameSlug,
            reply: reply,
            onSent: (id) {
              if (mounted) setState(() => _freshId = id);
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _delete(GameComment comment) async {
    final service = _service;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除评论？'),
        content: const Text('已有回复会保留。当前有效评分随这条评论取消。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        mounted &&
        service != null &&
        identical(service, _service)) {
      await _work(() => service.delete(comment));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final service = _service;
    if (service == null) {
      final account = AccountScope.maybeOf(context);
      final unavailable = account != null && !account.supportsSignIn;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Text(
              '评论',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              unavailable
                  ? '请在 App 或桌面端登录后查看评论'
                  : account?.isSignedIn == true
                  ? '评论连接尚未就绪，请联网后重试'
                  : '登录后查看评论与桌友评分',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
            if (!unavailable)
              TextButton(
                onPressed: () {
                  if (account?.isSignedIn == true) {
                    unawaited(_work(() => account!.restore()));
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AccountScreen(),
                      ),
                    );
                  }
                },
                child: Text(account?.isSignedIn == true ? '重试连接' : '登录'),
              ),
          ],
        ),
      );
    }
    final projection = service.projection;
    final comments = projection.forGame(
      widget.gameSlug,
      service.pendingIds,
      latest: _latest,
    );
    final roots = comments.where((c) => c.operation.root == null).toList();
    final fresh = roots.where((c) => c.id == _freshId).firstOrNull;
    if (fresh != null) {
      roots.remove(fresh);
      roots.insert(0, fresh);
    }
    final root = widget.rootId == null
        ? null
        : projection.comments[widget.rootId];
    final replies =
        comments
            .where(
              (c) => c.operation.root == widget.rootId && widget.rootId != null,
            )
            .toList()
          ..sort((a, b) => a.operation.at.compareTo(b.operation.at));
    final mobile = MediaQuery.sizeOf(context).width < 760;
    final visible = widget.rootId == null ? roots : replies;
    final displayed = visible.take(widget.preview ? 3 : _limit).toList();
    if (widget.rootId != null) {
      final freshReply = visible.where((c) => c.id == _freshId).firstOrNull;
      if (freshReply != null && !displayed.contains(freshReply)) {
        displayed.add(freshReply);
        displayed.sort((a, b) => a.operation.at.compareTo(b.operation.at));
      }
    }
    return Column(
      key: const ValueKey('game-comments-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              widget.rootId == null
                  ? '评论 ${roots.where((c) => !c.deleted).length}'
                  : '回复 ${replies.where((c) => !c.deleted).length}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.rootId == null && !widget.preview) ...[
                  TextButton(
                    onPressed: () => setState(() {
                      _latest = false;
                      _limit = 20;
                      _freshId = null;
                    }),
                    child: Text(
                      '热门',
                      style: TextStyle(
                        color: _latest
                            ? palette.textSecondary
                            : palette.primary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _latest = true;
                      _limit = 20;
                      _freshId = null;
                    }),
                    child: Text(
                      '最新',
                      style: TextStyle(
                        color: _latest
                            ? palette.primary
                            : palette.textSecondary,
                      ),
                    ),
                  ),
                ],
                IconButton(
                  tooltip: service.loading ? '正在刷新评论' : '刷新评论',
                  onPressed: service.loading ? null : service.synchronize,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (service.error != null &&
            (_likeErrors.isEmpty || comments.any((c) => c.pending)))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(service.error!, style: TextStyle(color: palette.warning)),
                TextButton(
                  onPressed: service.loading ? null : service.synchronize,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        if (!mobile &&
            !widget.preview &&
            (widget.rootId == null ||
                root != null && !projection.deleted.contains(root.id)))
          _CommentComposer(
            key: ValueKey(
              '${service.scope}|${widget.gameSlug}|${widget.rootId}',
            ),
            service: service,
            game: widget.gameSlug,
            reply: root == null
                ? null
                : comments.where((c) => c.id == root.id).firstOrNull,
            onSent: (id) => setState(() => _freshId = id),
          ),
        if (root != null) ...[
          _tile(
            GameComment(
              operation: root,
              deleted: projection.deleted.contains(root.id),
              likes:
                  comments.where((c) => c.id == root.id).firstOrNull?.likes ??
                  0,
              likedByMe:
                  comments
                      .where((c) => c.id == root.id)
                      .firstOrNull
                      ?.likedByMe ??
                  false,
              pending: service.pendingIds.contains(root.id),
            ),
            comments,
            rootContext: true,
          ),
          const Divider(height: 24),
        ],
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text(
              service.loading
                  ? '正在加载评论…'
                  : widget.rootId == null
                  ? '还没有评论，聊聊你的桌游体验吧'
                  : '还没有回复',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary),
            ),
          ),
        for (final comment in displayed) ...[
          _tile(comment, comments),
          Divider(height: 24, color: palette.outline.withValues(alpha: .25)),
        ],
        if (widget.preview)
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GameCommentsPage(
                  gameSlug: widget.gameSlug,
                  gameTitle: widget.gameTitle,
                  service: widget.service,
                ),
              ),
            ),
            child: const Text('查看全部评论'),
          ),
        if (!widget.preview && visible.length > _limit)
          TextButton(
            onPressed: () => setState(() => _limit += 20),
            child: const Text('加载更多'),
          ),
        if (widget.preview)
          OutlinedButton.icon(
            onPressed: service.canWrite ? () => _compose() : null,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('写评论'),
          ),
      ],
    );
  }

  Widget _tile(
    GameComment comment,
    List<GameComment> all, {
    bool rootContext = false,
  }) {
    final palette = AppPalette.of(context), service = _service!;
    final op = comment.operation;
    final parent = all.where((v) => v.id == op.replyTo).firstOrNull;
    final replies =
        all.where((c) => c.operation.root == comment.id && !c.deleted).toList()
          ..sort((a, b) => a.operation.at.compareTo(b.operation.at));
    return Row(
      key: ValueKey('comment-${comment.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: palette.secondaryContainer,
          foregroundColor: palette.onSecondaryContainer,
          child: const Icon(Icons.person_outline_rounded, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    comment.deleted ? '已删除' : op.author,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                    ),
                  ),
                  if (!comment.deleted && op.rating != null)
                    Text(
                      '${op.rating} 分',
                      style: TextStyle(color: palette.primary, fontSize: 12),
                    ),
                  if (comment.pending)
                    Text(
                      service.error == null ? '发送中' : '待重试',
                      style: TextStyle(color: palette.warning, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (parent != null && !comment.deleted && op.replyTo != op.root)
                Text(
                  '回复 ${parent.deleted ? '已删除评论' : parent.operation.author}',
                  style: TextStyle(color: palette.primary, fontSize: 12),
                ),
              SelectableText(
                comment.deleted ? '评论已删除' : op.text,
                style: TextStyle(
                  color: comment.deleted
                      ? palette.textSecondary
                      : palette.textPrimary,
                  height: 1.5,
                ),
              ),
              if (!comment.deleted)
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _time(op.at),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    TextButton.icon(
                      key: ValueKey('comment-like-${comment.id}'),
                      onPressed: service.canWrite && !_likeBusy(comment.id)
                          ? () => _like(comment)
                          : null,
                      icon: _likeBusy(comment.id)
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              comment.likedByMe
                                  ? Icons.thumb_up_alt_rounded
                                  : Icons.thumb_up_alt_outlined,
                              size: 16,
                            ),
                      label: Text('${comment.likes}'),
                      style: TextButton.styleFrom(
                        foregroundColor: comment.likedByMe
                            ? palette.primary
                            : palette.textSecondary,
                      ),
                    ),
                    if (_likeErrors[comment.id] != null ||
                        service.error != null &&
                            service.likePending(comment.id))
                      TextButton(
                        onPressed: _likeBusy(comment.id)
                            ? null
                            : () async {
                                final service = _service!;
                                if (!_liking.add(comment.id)) return;
                                setState(() {});
                                await service.synchronize();
                                if (mounted && identical(service, _service)) {
                                  setState(() {
                                    _liking.remove(comment.id);
                                    if (service.error == null) {
                                      _likeErrors.remove(comment.id);
                                    }
                                  });
                                }
                              },
                        child: const Text('重试点赞同步'),
                      ),
                    TextButton(
                      onPressed: service.canWrite
                          ? () => _compose(comment)
                          : null,
                      child: const Text('回复'),
                    ),
                    if (op.uid == service.uid)
                      PopupMenuButton<String>(
                        popUpAnimationStyle: AppMotion.menuStyle(context),
                        tooltip: '更多操作',
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除'),
                          ),
                        ],
                        onSelected: (_) => _delete(comment),
                        icon: const Icon(Icons.more_horiz_rounded, size: 18),
                      ),
                  ],
                ),
              if (!rootContext && widget.rootId == null && replies.isNotEmpty)
                Material(
                  color: palette.surfaceContainer.withValues(alpha: .6),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _openReplies(comment),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final reply in replies.take(2))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${reply.operation.author}：${reply.operation.text}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          Text(
                            '共 ${replies.length} 条回复，点击查看',
                            style: TextStyle(
                              color: palette.primary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _time(DateTime date) {
    final elapsed = DateTime.now().toUtc().difference(date);
    if (elapsed.inMinutes < 1) return '刚刚';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} 分钟前';
    if (elapsed.inDays < 1) return '${elapsed.inHours} 小时前';
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class GameCommentsPage extends StatefulWidget {
  const GameCommentsPage({
    super.key,
    required this.gameSlug,
    required this.gameTitle,
    this.rootId,
    this.service,
  });
  final String gameSlug, gameTitle;
  final String? rootId;
  final GameCommentsService? service;
  @override
  State<GameCommentsPage> createState() => _GameCommentsPageState();
}

class _GameCommentsPageState extends State<GameCommentsPage> {
  String? _freshId;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String get gameSlug => widget.gameSlug;
  String get gameTitle => widget.gameTitle;
  String? get rootId => widget.rootId;
  GameCommentsService? get service => widget.service;
  @override
  Widget build(BuildContext context) {
    final active = service ?? AccountScope.maybeOf(context)?.comments;
    final replyTarget = rootId == null
        ? null
        : active?.projection
              .forGame(gameSlug, active.pendingIds)
              .where((c) => c.id == rootId && !c.deleted)
              .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          rootId == null ? '评论 · $gameTitle' : '回复',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        child: GameCommentsPanel(
          gameSlug: gameSlug,
          gameTitle: gameTitle,
          rootId: rootId,
          service: service,
          recentCommentId: _freshId,
        ),
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width >= 760
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(12),
              child: FilledButton.icon(
                icon: const Icon(Icons.edit_outlined),
                label: Text(rootId == null ? '写评论' : '写回复'),
                onPressed:
                    active?.canWrite != true ||
                        rootId != null && replyTarget == null
                    ? null
                    : () => showAppBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (context) => Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            16,
                            16,
                            MediaQuery.viewInsetsOf(context).bottom + 16,
                          ),
                          child: SingleChildScrollView(
                            child: _CommentComposer(
                              service: active!,
                              game: gameSlug,
                              reply: replyTarget,
                              onSent: (id) {
                                if (mounted) setState(() => _freshId = id);
                                Navigator.of(context).pop();
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (!mounted || !_scroll.hasClients) return;
                                  final offset = rootId == null
                                      ? 0.0
                                      : _scroll.position.maxScrollExtent;
                                  if (AppMotion.reduced(this.context)) {
                                    _scroll.jumpTo(offset);
                                  } else {
                                    _scroll.animateTo(
                                      offset,
                                      duration: AppMotion.scroll,
                                      curve: AppMotion.curve,
                                    );
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      ),
              ),
            ),
    );
  }
}

class _CommentComposer extends StatefulWidget {
  const _CommentComposer({
    super.key,
    required this.service,
    required this.game,
    this.reply,
    required this.onSent,
  });
  final GameCommentsService service;
  final String game;
  final GameComment? reply;
  final ValueChanged<String> onSent;
  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  final _text = TextEditingController();
  String _id = GameCommentsService.newId();
  int? _rating;
  bool _ready = false, _sending = false, _enqueued = false;
  bool _finishing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.service.addListener(_confirmed);
    unawaited(_load());
  }

  void _confirmed() {
    if (mounted &&
        _ready &&
        _enqueued &&
        !_sending &&
        !_finishing &&
        !widget.service.pendingIds.contains(_id) &&
        widget.service.projection.comments.containsKey(_id)) {
      unawaited(
        _finishSent().catchError((Object _) {
          if (mounted) setState(() => _error = '评论已发送，草稿清理未完成，请重试');
        }),
      );
    }
  }

  Future<void> _finishSent() async {
    if (_finishing) return;
    _finishing = true;
    try {
      final sent = _id;
      await widget.service.saveDraft(widget.game, widget.reply?.id, null);
      if (!mounted) return;
      setState(() {
        _text.clear();
        _rating = null;
        _id = GameCommentsService.newId();
        _enqueued = false;
        _error = null;
      });
      widget.onSent(sent);
    } finally {
      _finishing = false;
    }
  }

  Future<void> _load() async {
    try {
      final draft = await widget.service.readDraft(
        widget.game,
        widget.reply?.id,
      );
      if (!mounted) return;
      if (draft != null) {
        _text.text = draft['text'] as String;
        _id = draft['id'] as String;
        _rating = draft['rating'] as int?;
        _enqueued = draft['enqueued'] as bool? ?? false;
        _enqueued = _enqueued || widget.service.pendingIds.contains(_id);
      }
      setState(() => _ready = true);
      _confirmed();
    } catch (_) {
      if (mounted) setState(() => _error = '草稿读取未完成，请重试');
    }
  }

  Future<void> _persist() => widget.service.saveDraft(
    widget.game,
    widget.reply?.id,
    {'id': _id, 'text': _text.text, 'rating': _rating, 'enqueued': _enqueued},
  );
  void _edited() {
    if (mounted) setState(() => _error = null);
    unawaited(
      _persist().catchError((Object _) {
        if (mounted) setState(() => _error = '草稿未保存，请重试');
      }),
    );
  }

  Future<void> _send() async {
    if (!_ready || _sending || _text.text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _persist();
      await widget.service.publish(
        game: widget.game,
        text: _text.text,
        rating: _rating,
        parent: widget.reply?.id,
        operationId: _id,
      );
      _enqueued = true;
      await _persist();
      await widget.service.synchronize();
      if (!mounted) return;
      if (widget.service.pendingIds.contains(_id)) {
        setState(() => _error = widget.service.error ?? '发送未完成，请重试');
        return;
      }
      await _finishSent();
    } catch (failure) {
      if (mounted) {
        setState(
          () => _error = failure is StateError
              ? failure.message.toString()
              : '发送未完成，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_confirmed);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.reply != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('回复 ${widget.reply!.operation.author}'),
          ),
        TextField(
          key: const ValueKey('comment-input'),
          controller: _text,
          enabled: _ready && !_sending && !_enqueued,
          onChanged: (_) => _edited(),
          minLines: 2,
          maxLines: 6,
          maxLength: 1000,
          decoration: InputDecoration(
            hintText: widget.reply == null ? '聊聊你的桌游体验…' : '写下你的回复…',
            border: const OutlineInputBorder(),
          ),
        ),
        _actions(),
        if (_error != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: AppPalette.of(context).error),
                ),
              ),
              if (!_ready)
                TextButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
      ],
    ),
  );

  Widget _actions() => LayoutBuilder(
    builder: (context, constraints) {
      final send = FilledButton.icon(
        key: const ValueKey('comment-send'),
        onPressed:
            _sending ||
                !_ready ||
                !widget.service.canWrite ||
                _text.text.trim().isEmpty
            ? null
            : _send,
        icon: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_rounded, size: 18),
        label: Text(_enqueued ? '重试发送' : '发布'),
      );
      if (widget.reply != null) {
        return Align(alignment: Alignment.centerRight, child: send);
      }
      final stars = _CommentStarRating(
        value: _rating,
        onChanged: !_ready || _sending || _enqueued
            ? null
            : (value) {
                setState(() => _rating = value);
                _edited();
              },
      );
      if (constraints.maxWidth >= 360 &&
          MediaQuery.textScalerOf(context).scale(14) <= 18) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [stars, send],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          stars,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerRight, child: send),
        ],
      );
    },
  );
}

/// Five stars represent ten integer points. Each half is selectable; selecting
/// the current point again clears the optional rating. No separate menu/label.
class _CommentStarRating extends StatelessWidget {
  const _CommentStarRating({required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?>? onChanged;
  void _step(int delta) {
    final next = ((value ?? 0) + delta).clamp(0, 10);
    onChanged?.call(next == 0 ? null : next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      label: '桌游评分',
      value: value == null ? '未评分' : '$value 分',
      increasedValue: '${((value ?? 0) + 1).clamp(0, 10)} 分',
      decreasedValue: (value ?? 0) <= 1 ? '未评分' : '${value! - 1} 分',
      slider: true,
      enabled: onChanged != null,
      onIncrease: onChanged == null ? null : () => _step(1),
      onDecrease: onChanged == null ? null : () => _step(-1),
      child: Focus(
        canRequestFocus: onChanged != null,
        onKeyEvent: (_, event) {
          if (onChanged == null || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.arrowUp) {
            _step(1);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowDown) {
            _step(-1);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.delete ||
              key == LogicalKeyboardKey.backspace) {
            onChanged!(null);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          key: const ValueKey('comment-rating'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 5; index++)
              _star(context, index, palette.warning, palette.outline),
          ],
        ),
      ),
    );
  }

  Widget _star(BuildContext context, int index, Color selected, Color empty) {
    const size = 44.0;
    final full = (index + 1) * 2;
    final filled = (value ?? 0) - index * 2;
    var chosen = full;
    return Tooltip(
      message: '${full - 1}–$full 分，再点取消',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('comment-rating-star-${index + 1}'),
          borderRadius: BorderRadius.circular(size / 2),
          onTapDown: onChanged == null
              ? null
              : (details) => chosen = details.localPosition.dx < size / 2
                    ? full - 1
                    : full,
          onTap: onChanged == null
              ? null
              : () => onChanged!(value == chosen ? null : chosen),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              filled >= 2
                  ? Icons.star_rounded
                  : filled == 1
                  ? Icons.star_half_rounded
                  : Icons.star_border_rounded,
              size: 28,
              color: filled > 0 ? selected : empty,
              semanticLabel: '$full 分',
            ),
          ),
        ),
      ),
    );
  }
}
