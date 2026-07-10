import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech service for voice alerts.
///
/// Uses flutter_tts. Falls back silently if TTS is unavailable.
class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  FlutterTts? _tts;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _tts = FlutterTts();
      await _tts!.setLanguage('ar');
      await _tts!.setSpeechRate(0.5);
      await _tts!.setVolume(1.0);
      _initialized = true;
      debugPrint('[Voice] TTS initialized');
    } catch (e) {
      debugPrint('[Voice] TTS not available: $e');
    }
  }

  Future<void> speak(String message) async {
    if (!_initialized || _tts == null) return;
    try {
      await _tts!.stop();
      await _tts!.speak(message);
    } catch (e) {
      debugPrint('[Voice] Speak failed: $e');
    }
  }

  Future<void> stop() async {
    if (_tts == null) return;
    try {
      await _tts!.stop();
    } catch (_) {}
  }

  /// Speak an alert for a specific alert type.
  Future<void> speakAlert(String typeLabel) async {
    final msg = _alertMessage(typeLabel);
    await speak(msg);
  }

  String _alertMessage(String label) {
    switch (label) {
      case '🚔 شرطة':
        return 'انتباه. شرطة أمامك.';
      case '📸 رادار':
        return 'انتباه. رادار سرعة أمامك.';
      case '🧑‍💼 مراقب':
        return 'مراقب غلوفو قريب.';
      case '🚫 عميل سيء':
        return 'عميل سيء في المنطقة.';
      case '⚠️ خطر':
        return 'انتباه. خطر أمامك.';
      case '💥 حادث':
        return 'انتباه. حادث أمامك.';
      default:
        return '$label في المنطقة.';
    }
  }
}
