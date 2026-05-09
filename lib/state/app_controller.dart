import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/app_language.dart';
import '../models/chat_message.dart';
import '../models/color_scheme_option.dart';
import '../models/game_info.dart';
import '../services/ai_service.dart';
import '../services/preferences_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../theme/app_palette.dart';
import '../theme/palette_registry.dart';
import '../ui/app_copy.dart';
import '../ui/game_catalog.dart';

class AppController extends ChangeNotifier {
  AppController({
    required PreferencesService preferencesService,
    required AiService aiService,
    required SpeechService speechService,
    required TtsService ttsService,
  }) : _preferencesService = preferencesService,
       _aiService = aiService,
       _speechService = speechService,
       _ttsService = ttsService;

  final PreferencesService _preferencesService;
  final AiService _aiService;
  final SpeechService _speechService;
  final TtsService _ttsService;

  AppLanguage _language = AppLanguage.zhHans;
  ColorSchemeOption _colorScheme = ColorSchemeOption.classic;
  bool _voiceReplyEnabled = true;
  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isSending = false;
  String _selectedGameId = 'puerto-rico';
  final List<ChatMessage> _messages = <ChatMessage>[];

  AppLanguage get language => _language;
  ColorSchemeOption get colorScheme => _colorScheme;
  AppPalette get palette => PaletteRegistry.of(_colorScheme);
  bool get voiceReplyEnabled => _voiceReplyEnabled;
  bool get speechAvailable => _speechAvailable;
  bool get isListening => _isListening;
  bool get isSending => _isSending;
  AppCopy get copy => AppCopy(_language);
  List<GameInfo> get games => GameCatalog.allGames(_language);
  GameInfo get featuredGame => selectedGame;
  GameInfo get selectedGame => games.firstWhere(
    (game) => game.id == _selectedGameId,
    orElse: () => games.first,
  );
  UnmodifiableListView<ChatMessage> get messages =>
      UnmodifiableListView<ChatMessage>(_messages);

  Future<void> initialize() async {
    _language = await _preferencesService.loadLanguage();
    _colorScheme = await _preferencesService.loadColorScheme();
    _voiceReplyEnabled = await _preferencesService.loadVoiceReplyEnabled();
    try {
      _speechAvailable = await _speechService.initialize(
        onListeningStopped: _handleListeningStopped,
      );
    } catch (_) {
      _speechAvailable = false;
    }
    await _ttsService.initialize(_language);
    _ensureGreeting();
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage next) async {
    if (_language == next) {
      return;
    }

    _language = next;
    await _preferencesService.saveLanguage(next);
    await _ttsService.setLanguage(next);
    notifyListeners();
  }

  Future<void> setColorScheme(ColorSchemeOption next) async {
    if (_colorScheme == next) {
      return;
    }

    _colorScheme = next;
    await _preferencesService.saveColorScheme(next);
    notifyListeners();
  }

  void selectGame(String gameId) {
    if (_selectedGameId == gameId) {
      return;
    }
    _selectedGameId = gameId;
    notifyListeners();
  }

  Future<void> setVoiceReplyEnabled(bool enabled) async {
    _voiceReplyEnabled = enabled;
    await _preferencesService.saveVoiceReplyEnabled(enabled);
    if (!enabled) {
      await _ttsService.stop();
    }
    notifyListeners();
  }

  Future<void> speakMessage(String text) async {
    await _ttsService.setLanguage(_language);
    await _ttsService.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _ttsService.stop();
  }

  Future<void> startListening({
    required ValueChanged<String> onRecognizedText,
  }) async {
    if (!_speechAvailable || _isListening) {
      return;
    }

    _isListening = true;
    notifyListeners();

    await _speechService.startListening(
      language: _language,
      onResult: onRecognizedText,
      onListeningStopped: _handleListeningStopped,
    );
  }

  Future<void> stopListening() async {
    await _speechService.stopListening();
    _handleListeningStopped();
  }

  Future<void> clearConversation() async {
    await resetConversation();
  }

  Future<void> resetConversation({String? greeting}) async {
    _messages
      ..clear()
      ..add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.assistant,
          text: greeting ?? copy.assistantGreetingFor(selectedGame.title),
          timestamp: DateTime.now(),
        ),
      );
    await _ttsService.stop();
    notifyListeners();
  }

  Future<void> sendPrompt(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || _isSending) {
      return;
    }

    final userMessage = ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}-user',
      role: ChatRole.user,
      text: trimmed,
      timestamp: DateTime.now(),
    );

    _messages.add(userMessage);
    _isSending = true;
    notifyListeners();

    final reply = await _aiService.generateReply(
      prompt: trimmed,
      language: _language,
      game: featuredGame,
    );

    final assistantMessage = ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}-assistant',
      role: ChatRole.assistant,
      text: reply,
      timestamp: DateTime.now(),
    );

    _messages.add(assistantMessage);
    _isSending = false;
    notifyListeners();

    if (_voiceReplyEnabled) {
      await speakMessage(reply);
    }
  }

  Future<void> disposeServices() async {
    await _speechService.cancelListening();
    await _ttsService.stop();
  }

  void _ensureGreeting() {
    if (_messages.isEmpty) {
      _messages.add(
        ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: ChatRole.assistant,
          text: copy.assistantGreetingFor(selectedGame.title),
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  void _handleListeningStopped() {
    if (_isListening) {
      _isListening = false;
      notifyListeners();
    }
  }
}
