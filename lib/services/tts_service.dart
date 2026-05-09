import 'package:flutter_tts/flutter_tts.dart';

import '../models/app_language.dart';
import 'markdown_sanitizer.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _ready = false;
  String? _defaultEngine;

  Future<void> initialize(AppLanguage language) async {
    if (_initialized) {
      await setLanguage(language);
      return;
    }

    _tts.setStartHandler(() {
      _ready = true;
    });
    _tts.setCompletionHandler(() {});
    _tts.setErrorHandler((_) {
      _ready = false;
    });

    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.42);
      await _tts.setVolume(1.0);
      await _tts.setQueueMode(0);
      await _tts.setAudioAttributesForNavigation();
      _defaultEngine = await _tts.getDefaultEngine as String?;
      if (_defaultEngine != null && _defaultEngine!.isNotEmpty) {
        await _tts.setEngine(_defaultEngine!);
      }
      await setLanguage(language);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    _initialized = true;
  }

  Future<void> setLanguage(AppLanguage language) async {
    final locale = language == AppLanguage.zhHans ? 'zh-CN' : 'en-US';
    try {
      final available = await _tts.isLanguageAvailable(locale);
      if (available == true) {
        await _tts.setLanguage(locale);
      }
    } catch (_) {
      // 如果当前设备不支持目标语音语言，就继续使用系统默认语音。
    }
  }

  Future<void> speak(String text) async {
    final plainText = MarkdownSanitizer.toSpeechPlainText(text);
    if (plainText.isEmpty) {
      return;
    }

    if (!_initialized || !_ready) {
      return;
    }

    try {
      await _tts.stop();
      await _tts.speak(plainText);
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
