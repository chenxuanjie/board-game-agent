import 'package:flutter/material.dart';

/// Shared sidebar destinations. Themes own their composition and materials,
/// while labels, order and business destinations stay consistent.
const workspaceNavigation =
    <({String destination, String asset, String zh, String en, IconData icon})>[
      (
        destination: 'home',
        asset: 'sidebar_home.png',
        zh: '首页',
        en: 'Home',
        icon: Icons.home_rounded,
      ),
      (
        destination: 'games',
        asset: 'sidebar_library.png',
        zh: '游戏库',
        en: 'Game Library',
        icon: Icons.grid_view_rounded,
      ),
      (
        destination: 'assistant',
        asset: 'sidebar_ai.png',
        zh: 'AI助手',
        en: 'AI Assistant',
        icon: Icons.auto_awesome_rounded,
      ),
      (
        destination: 'favorites',
        asset: 'sidebar_likes.png',
        zh: '我的喜欢',
        en: 'My Likes',
        icon: Icons.favorite_outline_rounded,
      ),
      (
        destination: 'rankings',
        asset: 'sidebar_ranking.png',
        zh: '排行榜',
        en: 'Rankings',
        icon: Icons.local_fire_department_rounded,
      ),
      (
        destination: 'settings',
        asset: 'sidebar_settings.png',
        zh: '设置',
        en: 'Settings',
        icon: Icons.tune_rounded,
      ),
    ];
