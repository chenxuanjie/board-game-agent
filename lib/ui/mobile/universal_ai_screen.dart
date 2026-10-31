import 'package:flutter/material.dart';

import '../../app/state/app_controller.dart';
import 'assistant_chat_screen.dart';

class UniversalAiScreen extends StatelessWidget {
  const UniversalAiScreen({
    super.key,
    required this.controller,
    this.keyboardVisible,
  });

  final AppController controller;
  final bool? keyboardVisible;

  @override
  Widget build(BuildContext context) {
    return AssistantChatScreen(
      controller: controller,
      customTitle: controller.copy.globalAiTitle,
      useGlobalMode: true,
      keyboardVisible: keyboardVisible,
    );
  }
}
