import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/assistant/models/ai_conversation.dart';
import '../../features/games/models/game_info.dart';
import '../../features/library/models/remote_library_update.dart';
import '../../app/state/app_controller.dart';
import 'settings_screen.dart';
import 'game_detail_screen.dart';
import 'game_search_screen.dart';
import 'rule_materials_screen.dart';
import 'home_content.dart';
import 'library_content.dart';
import 'mine_content.dart';
import 'universal_ai_screen.dart';
import 'assistant_chat_screen.dart';
import 'national_day_screen.dart';

/// Compact app shell. Desktop and wide Web keep their own responsive shell.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onOpenAbout,
  });

  final AppController controller;
  final VoidCallback onOpenAbout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _showingLibraryUpdateDialog = false;
  RemoteLibraryUpdate? _lastSeenUpdate;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLibraryUpdate());
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastSeenUpdate = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkLibraryUpdate(),
      );
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = widget.controller.copy;
    return Scaffold(
      key: const ValueKey('mobile-home-root'),
      backgroundColor: const Color(0xFFFFFBF7),
      body: SafeArea(
        child: _tab == 0
            ? MobileHomeContent(
                controller: widget.controller,
                onSearch: () => _openSearch(),
                onOpenGame: _openGame,
                onOpenConversation: _openConversation,
                onOpenAi: _openAi,
                onFavorites: () => _openSearch(favoritesOnly: true),
                onSettings: _openSettings,
                onActivities: _openActivities,
                onRules: _openRuleMaterials,
                onOpenNationalDay: _openNationalDay,
              )
            : _tab == 1
            ? MobileLibraryContent(
                controller: widget.controller,
                onOpenGame: _openGame,
                onActivities: _openActivities,
                onProfile: _openSettings,
              )
            : _tab == 2
            ? UniversalAiScreen(controller: widget.controller)
            : _tab == 3
            ? MobileMineContent(
                controller: widget.controller,
                onOpenGame: _openGame,
                onFavorites: () => _openSearch(favoritesOnly: true),
                onRecentAll: () => _openSearch(recentOnly: true),
                onExplore: _openSearch,
                onActivities: _openActivities,
                onSettings: _openSettings,
              )
            : const SizedBox.shrink(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (index) {
          if (index == 2 &&
              widget.controller.selectedConversation?.isGlobal != true) {
            widget.controller.openGlobalAssistant();
          }
          setState(() => _tab = index);
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFFFF673F),
        unselectedItemColor: const Color(0xFF777D8B),
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(
              Icons.home_rounded,
              key: ValueKey('mobile-tab-home'),
            ),
            label: copy.localized('首页', 'Home'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(
              Icons.casino_rounded,
              key: ValueKey('mobile-tab-library'),
            ),
            label: copy.localized('桌游库', 'Library'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(
              Icons.smart_toy_rounded,
              key: ValueKey('mobile-tab-ai'),
            ),
            label: copy.localized('AI助手', 'AI helper'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(
              Icons.person_rounded,
              key: ValueKey('mobile-tab-mine'),
            ),
            label: copy.localized('我的', 'Me'),
          ),
        ],
      ),
    );
  }

  void _openNationalDay() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileNationalDayScreen(
          controller: widget.controller,
          onOpenGame: _openGame,
        ),
      ),
    );
  }

  void _openGame(GameInfo game) {
    unawaited(widget.controller.recordRecentlyViewed(game));
    widget.controller.selectGame(game.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            GameDetailScreen(controller: widget.controller, game: game),
      ),
    );
  }

  void _openConversation(AiConversation conversation) {
    widget.controller.selectConversation(conversation.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AssistantChatScreen(
          controller: widget.controller,
          useGlobalMode: conversation.isGlobal,
          customTitle: conversation.isGlobal
              ? widget.controller.copy.globalAiTitle
              : null,
        ),
      ),
    );
  }

  void _openSearch({bool favoritesOnly = false, bool recentOnly = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileGameSearchScreen(
          controller: widget.controller,
          favoritesOnly: favoritesOnly,
          recentOnly: recentOnly,
          onOpenGame: _openGame,
        ),
      ),
    );
  }

  void _openRuleMaterials() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MobileRuleMaterialsScreen(controller: widget.controller),
      ),
    );
  }

  void _openAi() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UniversalAiScreen(controller: widget.controller),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileSettingsScreen(
          controller: widget.controller,
          onOpenAbout: widget.onOpenAbout,
        ),
      ),
    );
  }

  void _openActivities() {
    final activities = widget.controller.activities;
    final copy = widget.controller.copy;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.localized('消息', 'Notifications'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (activities.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(copy.localized('暂无消息', 'No notifications')),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: activities.length,
                    itemBuilder: (_, index) => ListTile(
                      title: Text(activities[index].title),
                      subtitle: Text(activities[index].message),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    unawaited(widget.controller.markActivitiesRead());
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _checkLibraryUpdate();
  }

  void _checkLibraryUpdate() {
    if (!mounted || _showingLibraryUpdateDialog) return;
    final next = widget.controller.pendingLibraryUpdate;
    if (next == null || identical(next, _lastSeenUpdate)) return;
    _lastSeenUpdate = next;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showLibraryUpdateDialog(),
    );
  }

  Future<void> _showLibraryUpdateDialog() async {
    if (!mounted ||
        _showingLibraryUpdateDialog ||
        !widget.controller.shouldShowLibraryUpdatePrompt()) {
      return;
    }
    _showingLibraryUpdateDialog = true;
    final copy = widget.controller.copy;
    final update = widget.controller.pendingLibraryUpdate;
    final shouldUpdate = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(copy.libraryUpdateTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(copy.libraryUpdateMessage),
              if (update != null && update.changedGameTitles.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(update.changedGameTitles.take(5).join('、')),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(copy.updateLater),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(copy.updateNow),
          ),
        ],
      ),
    );
    _showingLibraryUpdateDialog = false;
    if (!mounted) return;
    if (shouldUpdate == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(copy.updatingNow)));
      await widget.controller.applyPendingLibraryUpdate();
    } else {
      widget.controller.dismissPendingLibraryUpdatePrompt();
    }
  }
}
