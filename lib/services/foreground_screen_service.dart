import 'package:flutter/foundation.dart';

/// Tracks which top-level screen the user is currently viewing so that
/// services like [HomeScreen] can decide whether to surface local
/// notifications (e.g. skip chat-message pings while the user is already
/// looking at the chat screen).
///
/// Use [ForegroundScreen.current] to read; call [set] / [clear] from a
/// screen's `initState` / `dispose` to keep the value accurate.
class ForegroundScreenService extends ChangeNotifier {
  static final ForegroundScreenService _instance =
      ForegroundScreenService._internal();
  factory ForegroundScreenService() => _instance;
  ForegroundScreenService._internal();

  ForegroundScreen _current = ForegroundScreen.unknown;
  ForegroundScreen get current => _current;

  /// True when the user is actively looking at the screen for [screen].
  bool isActive(ForegroundScreen screen) => _current == screen;

  void set(ForegroundScreen screen) {
    if (_current == screen) return;
    _current = screen;
    notifyListeners();
    debugPrint('[ForegroundScreen] -> $screen');
  }

  void clear(ForegroundScreen screen) {
    if (_current != screen) return;
    _current = ForegroundScreen.unknown;
    notifyListeners();
    debugPrint('[ForegroundScreen] cleared $screen');
  }
}

enum ForegroundScreen { unknown, map, chat, blacklist, settings, group }
