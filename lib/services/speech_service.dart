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
  String _lastStatus = 'notListening';

  bool get isAvailable => _available;
  bool get isListening => _speech.isListening;
  String? get lastError => _lastError;
  String get lastStatus => _lastStatus;

  Future<bool> initialize({VoidCallback? onListeningStopped}) async {
    if (_initialized) {
      return _available;
    }

    try {
      _lastError = null;
      _available = await _speech.initialize(
        debugLogging: false,
        onError: (SpeechRecognitionError error) {
          _lastError = '${error.errorMsg}: ${error.permanent}';
          onListeningStopped?.call();
        },
        onStatus: (String status) {
          _lastStatus = status;
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

  Future<bool> reinitialize({VoidCallback? onListeningStopped}) async {
    _initialized = false;
    _available = false;
    _locales = const <LocaleName>[];
    return initialize(onListeningStopped: onListeningStopped);
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

  Future<bool> startListening({
    required AppLanguage language,
    required ValueChanged<String> onResult,
    required VoidCallback onListeningStopped,
    ValueChanged<double>? onSoundLevel,
  }) async {
    if (!_available) {
      return false;
    }

    try {
      _lastError = null;
      final SpeechListenOptions options = SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        onDevice: false,
        autoPunctuation: true,
        enableHapticFeedback: false,
      );
      await _speech.listen(
        localeId: resolveLocaleId(language),
        listenOptions: options,
        listenFor: const Duration(seconds: 40),
        pauseFor: const Duration(seconds: 5),
        onSoundLevelChange: onSoundLevel,
        onResult: (SpeechRecognitionResult result) {
          onResult(result.recognizedWords);
          if (result.finalResult) {
            onListeningStopped();
          }
        },
      );
      return true;
    } on PlatformException catch (error) {
      _lastError = '${error.code}: ${error.message ?? 'speech platform error'}';
      onListeningStopped();
      return false;
    } catch (error) {
      _lastError = error.toString();
      onListeningStopped();
      return false;
    }
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
