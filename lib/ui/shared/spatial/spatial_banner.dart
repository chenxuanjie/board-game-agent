import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import 'spatial_primitives.dart';

class SpatialBanner extends StatefulWidget {
  const SpatialBanner({
    super.key,
    required this.onExplore,
    required this.onTopic,
    required this.onAssistant,
  });
  final VoidCallback onExplore, onTopic, onAssistant;
  @override
  State<SpatialBanner> createState() => _SpatialBannerState();
}

class _SpatialBannerState extends State<SpatialBanner> {
  final _pages = PageController();
  Timer? _timer;
  int _page = 0;
  bool _hover = false;
  static const paths = [
    'assets/desktop/home/banner_tonight.png',
    'assets/desktop/home/banner_gathering.png',
    'assets/desktop/home/banner_ai.png',
  ];
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted ||
          !_pages.hasClients ||
          _hover ||
          AppMotion.reduced(context) ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      _go((_page + 1) % paths.length);
    });
  }

  void _go(int page) {
    if (!_pages.hasClients) return;
    if (AppMotion.reduced(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SpatialHoverBox(
    hoverOffset: -3,
    child: MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF11120F)),
            PageView(
              controller: _pages,
              key: const ValueKey('spatial-banners'),
              onPageChanged: (index) => setState(() => _page = index),
              children: [
                for (var i = 0; i < paths.length; i++)
                  InkWell(
                    key: ValueKey('spatial-banner-$i'),
                    onTap: [
                      widget.onExplore,
                      widget.onTopic,
                      widget.onAssistant,
                    ][i],
                    child: Transform.scale(
                      scale: i == 0 ? 1.04 : 1,
                      child: Image.asset(
                        paths[i],
                        semanticLabel: const [
                          '发现桌游',
                          '国庆桌游聚会清单',
                          '桌游 AI 助手',
                        ][i],
                        fit: BoxFit.cover,
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
              ],
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Row(
                children: [
                  for (var i = 0; i < paths.length; i++)
                    InkWell(
                      key: ValueKey('spatial-banner-dot-$i'),
                      onTap: () => _go(i),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          width: i == _page ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _page ? Colors.white : Colors.white54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
