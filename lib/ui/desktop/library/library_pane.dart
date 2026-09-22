part of '../business_panes.dart';

class DesktopLibraryPane extends StatefulWidget {
  const DesktopLibraryPane({
    super.key,
    required this.controller,
    this.onOpenRules,
    this.filter,
    this.onFilterChanged,
  });

  final AppController controller;
  final ValueChanged<DesktopLibraryResource>? onOpenRules;
  final DesktopLibraryResourceType? filter;
  final ValueChanged<DesktopLibraryResourceType?>? onFilterChanged;

  @override
  State<DesktopLibraryPane> createState() => DesktopLibraryPaneState();
}

class DesktopLibraryPaneState extends State<DesktopLibraryPane> {
  String? _openingItemId;
  String? _downloadingItemId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.controller.refreshLibraryResources());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppCopy copy = widget.controller.copy;
    if (!widget.controller.hasGames) {
      return _DesktopNoGamesPane(
        controller: widget.controller,
        title: copy.desktopLibraryEmptyTitle,
        message: copy.desktopLibraryEmptyMessage,
      );
    }
    final AppPalette palette = AppPalette.of(context);
    final List<DesktopLibraryResource> items =
        widget.controller.libraryResources;
    final List<DesktopLibraryResource> visible = widget.filter == null
        ? items
        : items
              .where(
                (DesktopLibraryResource item) => item.type == widget.filter,
              )
              .toList(growable: false);
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    copy.desktopLibraryTitle,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _showImportComingSoon,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(copy.desktopImport),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey<String>('desktop-library-refresh'),
                  tooltip: copy.desktopRefreshLibrary,
                  onPressed: widget.controller.isRefreshingLibrary
                      ? null
                      : () => unawaited(
                          widget.controller.refreshLibraryResources(
                            force: true,
                          ),
                        ),
                  icon: widget.controller.isRefreshingLibrary
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
        ),
        if (widget.controller.libraryLoadState == LibraryLoadState.failure)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
            sliver: SliverToBoxAdapter(
              child: _LibraryStatusBanner(
                icon: Icons.cloud_off_rounded,
                color: palette.warning,
                message: copy.desktopLibraryUnavailable,
                detail: widget.controller.libraryLoadError,
                actionLabel: copy.desktopRetry,
                onAction: () => unawaited(
                  widget.controller.refreshLibraryResources(force: true),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.outline),
              ),
              child: Wrap(
                spacing: 4,
                children: <Widget>[
                  _LibraryFilterChip(
                    label: copy.desktopAll,
                    selected: widget.filter == null,
                    onTap: () => widget.onFilterChanged?.call(null),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopRulebook,
                    selected:
                        widget.filter == DesktopLibraryResourceType.rulebook,
                    onTap: () => widget.onFilterChanged?.call(
                      DesktopLibraryResourceType.rulebook,
                    ),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopFaq,
                    selected: widget.filter == DesktopLibraryResourceType.faq,
                    onTap: () => widget.onFilterChanged?.call(
                      DesktopLibraryResourceType.faq,
                    ),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopLibraryPlayerAid,
                    selected:
                        widget.filter == DesktopLibraryResourceType.playerAid,
                    onTap: () => widget.onFilterChanged?.call(
                      DesktopLibraryResourceType.playerAid,
                    ),
                  ),
                  _LibraryFilterChip(
                    label: copy.desktopLibraryOther,
                    selected: widget.filter == DesktopLibraryResourceType.other,
                    onTap: () => widget.onFilterChanged?.call(
                      DesktopLibraryResourceType.other,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (widget.controller.libraryLoadState == LibraryLoadState.loading &&
            items.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (widget.controller.libraryLoadState == LibraryLoadState.empty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 56),
              child: Center(child: Text(copy.desktopLibraryNoResources)),
            ),
          )
        else if (visible.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 56),
              child: Center(child: Text(copy.desktopLibraryFilterNoResources)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
            sliver: SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (BuildContext context, int index) {
                final DesktopLibraryResource resource = visible[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LibraryItemTile(
                    key: ValueKey<String>('library-item-${resource.id}'),
                    resource: resource,
                    copy: copy,
                    isLoading:
                        _openingItemId == resource.id ||
                        _downloadingItemId == resource.id,
                    isDownloading: _downloadingItemId == resource.id,
                    onOpen: () => _openItem(resource),
                    onOpenRules: widget.onOpenRules == null
                        ? null
                        : () => widget.onOpenRules!(resource),
                    onDownload: () => _downloadItem(resource),
                    onDelete: () => _deleteItem(resource),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _showImportComingSoon() {
    final AppCopy copy = widget.controller.copy;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copy.desktopImportComingSoon)));
  }

  Future<void> _openItem(DesktopLibraryResource resource) async {
    if (_openingItemId != null || _downloadingItemId != null) return;
    if (!resource.canOpen) {
      final AppCopy copy = widget.controller.copy;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(copy.desktopOpenUnavailableMessage)),
        );
      return;
    }

    setState(() => _openingItemId = resource.id);
    try {
      final ResolvedDocument? document = await widget.controller
          .resolveLibraryResource(resource);
      if (!mounted) return;
      if (document == null) {
        _showDocumentUnavailable(resource.title);
        return;
      }
      await _openResolvedDocument(
        document,
        '${resource.gameTitle} · ${_displayResourceTitle(resource)}',
      );
    } catch (error) {
      if (mounted) _showDocumentUnavailable(resource.title, error: error);
    } finally {
      if (mounted) setState(() => _openingItemId = null);
    }
  }

  Future<void> _downloadItem(DesktopLibraryResource resource) async {
    if (_openingItemId != null || _downloadingItemId != null) return;
    if (kIsWeb) {
      _showDownloadUnavailable('当前 Web 端不支持选择本地下载目录');
      return;
    }

    setState(() => _downloadingItemId = resource.id);
    try {
      final String? directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: widget.controller.copy.desktopDownloadDirectory,
      );
      if (!mounted || directory == null || directory.trim().isEmpty) {
        return;
      }
      final String? destination = await widget.controller
          .downloadLibraryResource(
            resource: resource,
            directoryPath: directory,
          );
      if (!mounted) return;
      if (destination == null) {
        _showDownloadUnavailable(widget.controller.copy.desktopDownloadFailed);
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              widget.controller.copy.desktopDownloadedTo(destination),
            ),
          ),
        );
    } catch (error) {
      if (mounted) {
        _showDownloadUnavailable(
          widget.controller.copy.desktopDownloadError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingItemId = null);
    }
  }

  void _deleteItem(DesktopLibraryResource resource) {
    final AppCopy copy = widget.controller.copy;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copy.desktopDeleteUnavailable)));
  }

  String _displayResourceTitle(DesktopLibraryResource resource) {
    final AppCopy copy = widget.controller.copy;
    switch (resource.type) {
      case DesktopLibraryResourceType.rulebook:
        return resource.isRemote
            ? copy.desktopRulebook
            : '官方${copy.desktopRulebook}';
      case DesktopLibraryResourceType.faq:
        return resource.isRemote ? copy.desktopFaq : '官方 ${copy.desktopFaq}';
      case DesktopLibraryResourceType.playerAid:
        return copy.desktopLibraryPlayerAid;
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.supplement:
      case DesktopLibraryResourceType.other:
        return resource.title.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    }
  }

  void _showDownloadUnavailable(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openResolvedDocument(
    ResolvedDocument document,
    String title,
  ) async {
    if (document.renderType == DocumentRenderType.markdown) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MarkdownDocumentScreen(
            controller: widget.controller,
            remotePath: document.remotePath,
            title: title,
          ),
        ),
      );
      return;
    }
    if (document.renderType != DocumentRenderType.pdf) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => LibraryResourceDocumentScreen(
            controller: widget.controller,
            document: document,
            title: title,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PdfDocumentScreen(
          controller: widget.controller,
          title: title,
          remotePath: document.remotePath,
        ),
      ),
    );
  }

  void _showDocumentUnavailable(String title, {Object? error}) {
    final String suffix = error == null ? '' : '：$error';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$title暂不可用$suffix')));
  }
}

class _LibraryStatusBanner extends StatelessWidget {
  const _LibraryStatusBanner({
    required this.icon,
    required this.color,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null && detail!.trim().isNotEmpty)
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _LibraryFilterChip extends StatelessWidget {
  const _LibraryFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: selected
            ? palette.primary.withValues(alpha: 0.16)
            : null,
        foregroundColor: selected ? palette.textPrimary : palette.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(
          color: selected ? palette.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Text(label),
    );
  }
}

class _LibraryItemTile extends StatelessWidget {
  const _LibraryItemTile({
    super.key,
    required this.resource,
    required this.copy,
    required this.isLoading,
    required this.isDownloading,
    required this.onOpen,
    this.onOpenRules,
    required this.onDownload,
    required this.onDelete,
  });

  final DesktopLibraryResource resource;
  final AppCopy copy;
  final bool isLoading;
  final bool isDownloading;
  final VoidCallback onOpen;
  final VoidCallback? onOpenRules;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = AppPalette.of(context);
    final IconData icon = switch (resource.type) {
      DesktopLibraryResourceType.rulebook => Icons.menu_book_outlined,
      DesktopLibraryResourceType.faq => Icons.fact_check_outlined,
      DesktopLibraryResourceType.assetIndex => Icons.description_outlined,
      DesktopLibraryResourceType.reference => Icons.description_outlined,
      DesktopLibraryResourceType.playerAid => Icons.description_outlined,
      DesktopLibraryResourceType.supplement => Icons.description_outlined,
      DesktopLibraryResourceType.other => Icons.description_outlined,
    };
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading || !resource.canOpen ? null : onOpen,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.outline),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: palette.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: palette.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${resource.gameTitle} · ${_displayTitle()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_typeLabel()} · ${_languageLabel()} · ${_formatLabel()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...<Widget>[
                if (onOpenRules != null)
                  TextButton(
                    onPressed: onOpenRules,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF66C0F4),
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(3),
                        side: const BorderSide(color: Color(0x4066C0F4)),
                      ),
                    ),
                    child: const Text('条款问答'),
                  ),
                PopupMenuButton<_LibraryItemAction>(
                  key: ValueKey<String>('library-more-${resource.id}'),
                  tooltip: copy.desktopMore,
                  onSelected: (_LibraryItemAction action) {
                    switch (action) {
                      case _LibraryItemAction.open:
                        onOpen();
                      case _LibraryItemAction.download:
                        onDownload();
                      case _LibraryItemAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<_LibraryItemAction>>[
                        PopupMenuItem<_LibraryItemAction>(
                          value: _LibraryItemAction.open,
                          enabled: resource.canOpen,
                          child: Text(
                            resource.canOpen
                                ? copy.desktopOpen
                                : copy.desktopOpenUnavailable,
                          ),
                        ),
                        PopupMenuItem<_LibraryItemAction>(
                          value: _LibraryItemAction.download,
                          child: Text(copy.desktopDownload),
                        ),
                        PopupMenuItem<_LibraryItemAction>(
                          value: _LibraryItemAction.delete,
                          child: Text(copy.desktopDelete),
                        ),
                      ],
                  icon: isDownloading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _displayTitle() {
    switch (resource.type) {
      case DesktopLibraryResourceType.rulebook:
        return copy.desktopRulebook;
      case DesktopLibraryResourceType.faq:
        return copy.desktopFaq;
      case DesktopLibraryResourceType.playerAid:
        return copy.desktopLibraryPlayerAid;
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.supplement:
      case DesktopLibraryResourceType.other:
        final String title = resource.title.trim();
        return title
            .replaceAll(RegExp(r'[_-]+'), ' ')
            .replaceFirst(RegExp(r'\.[^.]+$'), '')
            .trim();
    }
  }

  String _typeLabel() {
    switch (resource.type) {
      case DesktopLibraryResourceType.rulebook:
        return copy.desktopRulebook;
      case DesktopLibraryResourceType.faq:
        return copy.desktopFaq;
      case DesktopLibraryResourceType.assetIndex:
      case DesktopLibraryResourceType.reference:
      case DesktopLibraryResourceType.playerAid:
      case DesktopLibraryResourceType.supplement:
      case DesktopLibraryResourceType.other:
        return copy.desktopLibraryOther;
    }
  }

  String _languageLabel() {
    final String language = resource.language.trim();
    if (language == '中文') return copy.isChinese ? '中文' : 'Chinese';
    if (language == '英文') return copy.isChinese ? '英文' : 'English';
    if (language == '多语言') return copy.isChinese ? '多语言' : 'Multilingual';
    return copy.isChinese ? language : 'Unspecified';
  }

  String _formatLabel() {
    switch (resource.format) {
      case DesktopLibraryResourceFormat.markdown:
        return 'Markdown';
      case DesktopLibraryResourceFormat.pdf:
        return 'PDF';
      case DesktopLibraryResourceFormat.html:
        return 'HTML';
      case DesktopLibraryResourceFormat.text:
        return copy.isChinese ? '文本' : 'Text';
      case DesktopLibraryResourceFormat.image:
        return copy.isChinese ? '图片' : 'Image';
      case DesktopLibraryResourceFormat.other:
        return copy.isChinese ? '文件' : 'File';
    }
  }
}

enum _LibraryItemAction { open, download, delete }
