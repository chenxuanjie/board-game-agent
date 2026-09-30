part of 'business_panes.dart';

class DesktopRulesDrawer extends StatelessWidget {
  const DesktopRulesDrawer({
    super.key,
    required this.open,
    required this.tabIndex,
    required this.game,
    required this.resource,
    required this.controller,
    required this.onClose,
    required this.onTabChanged,
    required this.onOpenAssistant,
    required this.onOpenResource,
  });

  final bool open;
  final int tabIndex;
  final GameInfo? game;
  final DesktopLibraryResource? resource;
  final AppController controller;
  final VoidCallback onClose;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenResource;

  @override
  Widget build(BuildContext context) {
    if (!open) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !open,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          opacity: open ? 1 : 0,
          child: Stack(
            children: <Widget>[
              GestureDetector(
                onTap: onClose,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(color: const Color(0xB8000000)),
                ),
              ),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double width = math.min(
                    720,
                    constraints.maxWidth * 0.92,
                  );
                  return Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      offset: open ? Offset.zero : const Offset(1, 0),
                      child: SizedBox(
                        width: width,
                        height: constraints.maxHeight,
                        child: _RulesDrawerPanel(
                          game: game,
                          resource: resource,
                          controller: controller,
                          tabIndex: tabIndex,
                          onClose: onClose,
                          onTabChanged: onTabChanged,
                          onOpenAssistant: onOpenAssistant,
                          onOpenResource: onOpenResource,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RulesDrawerPanel extends StatelessWidget {
  const _RulesDrawerPanel({
    required this.game,
    required this.resource,
    required this.controller,
    required this.tabIndex,
    required this.onClose,
    required this.onTabChanged,
    required this.onOpenAssistant,
    required this.onOpenResource,
  });

  final GameInfo? game;
  final DesktopLibraryResource? resource;
  final AppController controller;
  final int tabIndex;
  final VoidCallback onClose;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenResource;

  String get _title {
    if (resource != null) return resource!.title;
    if (game != null) return '《${game!.title}》· 游戏档案';
    return '文档速览';
  }

  String get _subtitle {
    if (resource != null) {
      return '${resource!.gameTitle} · ${resource!.typeLabel} · ${resource!.formatLabel}';
    }
    if (game != null) return '已挂载当前桌游的本地资料';
    return '未选择桌游资料';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _desktopFeatureColor(
          context,
          Color(0xFF111722),
          AppPalette.of(context).surface,
        ),
        border: Border(
          left: BorderSide(
            color: _desktopFeatureColor(
              context,
              Color(0x12FFFFFF),
              AppPalette.of(context).outline,
            ),
          ),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0xE6000000),
            blurRadius: 60,
            offset: Offset(-20, 0),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Container(
            height: 56,
            padding: EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: _desktopFeatureColor(
                context,
                Color(0xB3121924),
                AppPalette.of(context).surfaceContainer,
              ),
              border: Border(
                bottom: BorderSide(
                  color: _desktopFeatureColor(
                    context,
                    Color(0x12FFFFFF),
                    AppPalette.of(context).outline,
                  ),
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _desktopFeatureColor(
                            context,
                            Colors.white,
                            AppPalette.of(context).textPrimary,
                          ),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        _subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _desktopFeatureColor(
                            context,
                            Color(0xFF8A96A3),
                            AppPalette.of(context).textSecondary,
                          ),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  tooltip: '关闭',
                  icon: Icon(Icons.close_rounded, size: 17),
                  color: _desktopFeatureColor(
                    context,
                    Color(0xFF8A96A3),
                    AppPalette.of(context).textSecondary,
                  ),
                  style: IconButton.styleFrom(
                    fixedSize: Size.square(28),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 42,
            padding: EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: _desktopFeatureColor(
                context,
                Color(0xFF0E131D),
                AppPalette.of(context).surfaceContainer,
              ),
              border: Border(
                bottom: BorderSide(
                  color: _desktopFeatureColor(
                    context,
                    Color(0x12FFFFFF),
                    AppPalette.of(context).outline,
                  ),
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                _RulesDrawerTab(
                  label: '规则速览',
                  selected: tabIndex == 0,
                  onTap: () => onTabChanged(0),
                ),
                SizedBox(width: 20),
                _RulesDrawerTab(
                  label: '规则裁决问答',
                  selected: tabIndex == 1,
                  onTap: () => onTabChanged(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: tabIndex == 0
                ? _RulesReaderContent(
                    game: game,
                    resource: resource,
                    onOpenResource: onOpenResource,
                  )
                : _RulesAssistantContent(
                    game: game,
                    onOpenAssistant: onOpenAssistant,
                  ),
          ),
        ],
      ),
    );
  }
}

class _RulesDrawerTab extends StatelessWidget {
  const _RulesDrawerTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 42,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? _desktopFeatureColor(
                        context,
                        Colors.white,
                        AppPalette.of(context).textPrimary,
                      )
                    : _desktopFeatureColor(
                        context,
                        Color(0xFF8A96A3),
                        AppPalette.of(context).textSecondary,
                      ),
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (selected)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 2,
                  child: ColoredBox(
                    color: _desktopFeatureColor(
                      context,
                      Color(0xFF66C0F4),
                      AppPalette.of(context).primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RulesReaderContent extends StatelessWidget {
  const _RulesReaderContent({
    required this.game,
    required this.resource,
    required this.onOpenResource,
  });

  final GameInfo? game;
  final DesktopLibraryResource? resource;
  final VoidCallback onOpenResource;

  @override
  Widget build(BuildContext context) {
    final List<String> roundFlow = game?.roundFlow ?? <String>[];
    final List<GameResource> resources =
        game?.resources
            .where(
              (GameResource item) =>
                  item.enabled && item.isAvailable && !item.isInOthersDirectory,
            )
            .toList(growable: false) ??
        <GameResource>[];
    final bool hasContent =
        game != null &&
        ((game!.summary.trim().isNotEmpty) ||
            roundFlow.isNotEmpty ||
            resources.isNotEmpty);
    return ListView(
      padding: EdgeInsets.all(28),
      children: <Widget>[
        Container(
          padding: EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: _desktopFeatureColor(
              context,
              Color(0x40000000),
              AppPalette.of(context).surfaceVariant,
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _desktopFeatureColor(
                context,
                Color(0x12FFFFFF),
                AppPalette.of(context).outline,
              ),
            ),
          ),
          child: !hasContent
              ? Text(
                  '暂无可用规则摘要。请先挂载规则书或 FAQ 资料。',
                  style: TextStyle(
                    color: _desktopFeatureColor(
                      context,
                      Color(0xFF8A96A3),
                      AppPalette.of(context).textSecondary,
                    ),
                    fontSize: 13,
                    height: 1.8,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (game != null) ...<Widget>[
                      Text(
                        '《${game!.title}》· 规则资料速览',
                        style: TextStyle(
                          color: _desktopFeatureColor(
                            context,
                            Colors.white,
                            AppPalette.of(context).textPrimary,
                          ),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 14),
                      if (game!.summary.trim().isNotEmpty)
                        Text(
                          game!.summary,
                          style: TextStyle(
                            color: _desktopFeatureColor(
                              context,
                              Color(0xFFC9D2DB),
                              AppPalette.of(context).textSecondary,
                            ),
                            fontSize: 13,
                            height: 1.8,
                          ),
                        ),
                      if (roundFlow.isNotEmpty) ...<Widget>[
                        SizedBox(height: 18),
                        Text(
                          '回合流程',
                          style: TextStyle(
                            color: _desktopFeatureColor(
                              context,
                              Color(0xFF66C0F4),
                              AppPalette.of(context).primary,
                            ),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        ...roundFlow.asMap().entries.map(
                          (MapEntry<int, String> entry) => Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Text(
                              '${entry.key + 1}. ${entry.value}',
                              style: TextStyle(
                                color: _desktopFeatureColor(
                                  context,
                                  Color(0xFFC9D2DB),
                                  AppPalette.of(context).textSecondary,
                                ),
                                fontSize: 13,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (resources.isNotEmpty) ...<Widget>[
                        SizedBox(height: 18),
                        Text(
                          '已挂载资料',
                          style: TextStyle(
                            color: _desktopFeatureColor(
                              context,
                              Color(0xFF66C0F4),
                              AppPalette.of(context).primary,
                            ),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        ...resources.map(
                          (GameResource item) => Padding(
                            padding: EdgeInsets.only(bottom: 5),
                            child: Text(
                              '• ${item.fileName} · ${item.format.toUpperCase()}',
                              style: TextStyle(
                                color: _desktopFeatureColor(
                                  context,
                                  Color(0xFFC9D2DB),
                                  AppPalette.of(context).textSecondary,
                                ),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (resource != null && resource!.canOpen) ...<Widget>[
                      SizedBox(height: 20),
                      TextButton.icon(
                        onPressed: onOpenResource,
                        icon: Icon(Icons.open_in_new_rounded, size: 15),
                        label: Text('打开原始资料'),
                        style: TextButton.styleFrom(
                          foregroundColor: _desktopFeatureColor(
                            context,
                            Color(0xFF66C0F4),
                            AppPalette.of(context).primary,
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _RulesAssistantContent extends StatelessWidget {
  const _RulesAssistantContent({
    required this.game,
    required this.onOpenAssistant,
  });

  final GameInfo? game;
  final VoidCallback onOpenAssistant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                constraints: BoxConstraints(maxWidth: 560),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _desktopFeatureColor(
                    context,
                    Color(0xB3161F2C),
                    AppPalette.of(context).surfaceVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _desktopFeatureColor(
                      context,
                      Color(0x12FFFFFF),
                      AppPalette.of(context).outline,
                    ),
                  ),
                ),
                child: Text(
                  game == null
                      ? '请选择一款桌游后再进入规则裁决问答。'
                      : '这里会继续使用《${game!.title}》的真实 AI 会话。打开助手后，回答、引用和运行过程会保留在同一会话中。',
                  style: TextStyle(
                    color: _desktopFeatureColor(
                      context,
                      Color(0xFFF0F3F7),
                      AppPalette.of(context).textPrimary,
                    ),
                    fontSize: 12.5,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: _desktopFeatureColor(
                    context,
                    Color(0x12FFFFFF),
                    AppPalette.of(context).outline,
                  ),
                ),
              ),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOpenAssistant,
                icon: Icon(Icons.chat_bubble_outline_rounded, size: 15),
                label: Text('打开桌游助手'),
                style: TextButton.styleFrom(
                  foregroundColor: _desktopFeatureColor(
                    context,
                    Color(0xFF66C0F4),
                    AppPalette.of(context).primary,
                  ),
                  backgroundColor: _desktopFeatureColor(
                    context,
                    Color(0x1A66C0F4),
                    AppPalette.of(context).primaryContainer,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
