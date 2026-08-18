import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import 'assistant_chat_screen.dart';

class UniversalAiScreen extends StatelessWidget {
  const UniversalAiScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AssistantChatScreen(
      controller: controller,
      customTitle: controller.copy.globalAiTitle,
      customSubtitle: controller.copy.globalAiSubtitle,
      useGlobalMode: true,
    );
  }
}
