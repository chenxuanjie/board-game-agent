import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/app_language.dart';
import 'markdown_sanitizer.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _ready = false;
  bool _speaking = false;
  Future<void> _operationQueue = Future<void>.value();

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isAvailable => !_isWindows;

  Future<void> _enqueue(Future<void> Function() operation) {
    final Future<void> next = _operationQueue.then((_) => operation());
    // Keep the queue usable after a failed platform call while preserving the
    // error for the caller that started this operation.
    _operationQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> initialize(AppLanguage language) async {
    if (_initialized) {
      await setLanguage(language);
      return;
    }

    // flutter_tts 4.2.5 currently sends Windows native callbacks from a
    // worker thread. That is unsafe for Flutter's Windows platform channel
    // and has caused access violations in flutter_tts_plugin.dll. Keep the
    // desktop app stable until the upstream plugin marshals those callbacks
    // correctly; Android and Web continue to use the normal implementation.
    if (_isWindows) {
      _initialized = true;
      _ready = false;
      return;
    }

    _tts.setStartHandler(() {
      _ready = true;
      _speaking = true;
    });
    _tts.setCompletionHandler(() {
      _speaking = false;
    });
    _tts.setCancelHandler(() {
      _speaking = false;
    });
    _tts.setErrorHandler((_) {
      _ready = false;
      _speaking = false;
    });

    try {
      // The Windows implementation uses an unsafe native wait callback when
      // completion is awaited. Keep completion asynchronous there; callers do
      // not need to block on native SAPI playback.
      await _tts.awaitSpeakCompletion(!_isWindows);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.42);
      await _tts.setVolume(1.0);
      if (_isAndroid) {
        await _tts.setQueueMode(0);
        await _tts.setAudioAttributesForNavigation();
        final defaultEngine = await _tts.getDefaultEngine;
        if (defaultEngine is String && defaultEngine.trim().isNotEmpty) {
          await _tts.setEngine(defaultEngine);
        }
      }
      await _setLanguageInternal(language);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    _initialized = true;
  }

  Future<void> setLanguage(AppLanguage language) {
    if (!isAvailable) {
      return Future<void>.value();
    }
    if (!_initialized) {
      return _setLanguageInternal(language);
    }
    return _enqueue(() => _setLanguageInternal(language));
  }

  Future<void> _setLanguageInternal(AppLanguage language) async {
    final locale = language == AppLanguage.zhHans ? 'zh-CN' : 'en-US';
    try {
      // Windows supports setLanguage through SAPI but does not implement the
      // plugin's isLanguageAvailable method.
      if (_isWindows) {
        await _tts.setLanguage(locale);
        return;
      }
      final available = await _tts.isLanguageAvailable(locale);
      if (available == true) {
        await _tts.setLanguage(locale);
      }
    } catch (_) {
      // 如果当前设备不支持目标语音语言，就继续使用系统默认语音。
    }
  }

  Future<void> speak(String text) {
    if (!isAvailable) {
      return Future<void>.value();
    }
    return _enqueue(() async {
      final plainText = MarkdownSanitizer.toSpeechPlainText(text);
      if (plainText.isEmpty || !_initialized || !_ready) {
        return;
      }

      try {
        // Do not send a redundant stop to Windows SAPI. If a previous utterance
        // is still active, stop it once, in the same serialized operation.
        if (_speaking) {
          await _tts.stop();
          _speaking = false;
        }
        await _tts.speak(plainText);
      } catch (_) {
        _ready = false;
        _speaking = false;
      }
    });
  }

  Future<void> stop() {
    if (!isAvailable) {
      return Future<void>.value();
    }
    return _enqueue(() async {
      try {
        await _tts.stop();
      } catch (_) {
        _ready = false;
      } finally {
        _speaking = false;
      }
    });
  }
}
