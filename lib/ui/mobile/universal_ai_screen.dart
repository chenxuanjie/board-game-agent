import 'package:flutter/material.dart';

import '../../app/state/app_controller.dart';
import 'assistant_chat_screen.dart';

class UniversalAiScreen extends StatelessWidget {
  const UniversalAiScreen({
    super.key,
    required this.controller,
    this.accountActions,
  });

  final AppController controller;
  final Widget? accountActions;

  @override
  Widget build(BuildContext context) {
    return AssistantChatScreen(
      controller: controller,
      customTitle: controller.copy.globalAiTitle,
      useGlobalMode: true,
      accountActions: accountActions,
    );
  }
}
