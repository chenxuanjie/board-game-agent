import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/app_language.dart';

class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _available = false;
  List<LocaleName> _locales = const <LocaleName>[];
  String? _lastError;

  bool get isAvailable => _available;
  bool get isListening => _speech.isListening;
  String? get lastError => _lastError;

  Future<bool> initialize({VoidCallback? onListeningStopped}) async {
    if (_initialized) {
      return _available;
    }

    try {
      _lastError = null;
      _available = await _speech.initialize(
        debugLogging: false,
        onError: (SpeechRecognitionError _) {
          onListeningStopped?.call();
        },
        onStatus: (String status) {
          if (status == 'done' || status == 'notListening') {
            onListeningStopped?.call();
          }
        },
      );

      if (_available) {
        _locales = await _speech.locales();
      }
    } on PlatformException catch (error) {
      _available = false;
      _locales = const <LocaleName>[];
      _lastError = '${error.code}: ${error.message ?? 'speech platform error'}';
    } catch (error) {
      _available = false;
      _locales = const <LocaleName>[];
      _lastError = error.toString();
    }

    _initialized = true;
    return _available;
  }

  String resolveLocaleId(AppLanguage language) {
    final preferred = language.speechLocale.toLowerCase();
    for (final locale in _locales) {
      if (locale.localeId.toLowerCase() == preferred) {
        return locale.localeId;
      }
    }

    final prefix = preferred.split('_').first;
    for (final locale in _locales) {
      if (locale.localeId.toLowerCase().startsWith(prefix)) {
        return locale.localeId;
      }
    }

    return language.speechLocale;
  }

  Future<void> startListening({
    required AppLanguage language,
    required ValueChanged<String> onResult,
    required VoidCallback onListeningStopped,
  }) async {
    if (!_available) {
      return;
    }

    await _speech.listen(
      localeId: resolveLocaleId(language),
      listenMode: ListenMode.confirmation,
      partialResults: true,
      cancelOnError: true,
      listenFor: const Duration(seconds: 40),
      pauseFor: const Duration(seconds: 4),
      onResult: (SpeechRecognitionResult result) {
        onResult(result.recognizedWords);
        if (result.finalResult) {
          onListeningStopped();
        }
      },
    );
  }

  Future<void> stopListening() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
  }

  Future<void> cancelListening() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }
}
