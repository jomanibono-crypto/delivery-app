import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's name, group code, avatar icon, and notification mute
/// state locally using shared_preferences.
class LocalStorageService {
  static const _userNameKey = 'user_name';
  static const _groupCodeKey = 'group_code';
  static const _userIconKey = 'user_icon'; // emoji string, e.g. '🚗'
  static const _mutedUntilKey = 'muted_until'; // epoch ms, 0 = not muted
  // PART 2: selected proximity sound. Values: 'default','chime1','chime2','chime3','silent'
  static const _notifSoundKey = 'notif_sound';
  // PART 2: incremented channel version (channels are immutable on Android).
  static const _channelVersionKey = 'proximity_channel_version';
  // PART 4: flag so the popup-notification dialog shows only once.
  static const _popupNotifRequestedKey = 'popup_notif_requested';

  // ──────────────────── Session ────────────────────

  /// Save the user's name and group code.
  Future<void> saveSession({
    required String userName,
    required String groupCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, userName);
    await prefs.setString(_groupCodeKey, groupCode);
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  Future<String?> getGroupCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_groupCodeKey);
  }

  Future<bool> hasSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_userNameKey) &&
        prefs.containsKey(_groupCodeKey);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userNameKey);
    await prefs.remove(_groupCodeKey);
    // Keep the icon + mute state across sessions — they're device prefs,
    // not group-specific.
  }

  // ──────────────────── Avatar Icon (F1) ────────────────────

  Future<void> saveUserIcon(String emoji) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIconKey, emoji);
  }

  Future<String?> getUserIcon() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIconKey);
  }

  // ──────────────────── Notification Mute (F3) ────────────────────

  /// Save the epoch-ms timestamp until which notifications are muted.
  /// Pass 0 (or null) to clear muting.
  Future<void> setMutedUntil(int? epochMs) async {
    final prefs = await SharedPreferences.getInstance();
    if (epochMs == null || epochMs <= 0) {
      await prefs.remove(_mutedUntilKey);
    } else {
      await prefs.setInt(_mutedUntilKey, epochMs);
    }
  }

  /// Returns the epoch-ms until which notifications are muted, or 0 if not muted.
  Future<int> getMutedUntil() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_mutedUntilKey) ?? 0;
  }

  /// True if notifications are currently muted (muted_until is in the future).
  Future<bool> isCurrentlyMuted() async {
    final until = await getMutedUntil();
    return until > DateTime.now().millisecondsSinceEpoch;
  }

  // ──────────────────── Notification Sound (PART 2) ────────────────────

  /// Save the selected proximity sound key.
  /// Valid values: 'default', 'chime1', 'chime2', 'chime3', 'silent'.
  Future<void> setNotifSound(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notifSoundKey, key);
  }

  /// Returns the saved sound key, defaulting to 'default'.
  Future<String> getNotifSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_notifSoundKey) ?? 'default';
  }

  /// Incremented whenever the sound changes, so we build a fresh (immutable)
  /// Android notification channel each time.
  Future<int> getChannelVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_channelVersionKey) ?? 2; // v2 was the last one used
  }

  Future<void> setChannelVersion(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_channelVersionKey, v);
  }

  // ──────────────────── Popup Notification Permission (PART 4) ────────────────────

  Future<bool> wasPopupNotifRequested() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_popupNotifRequestedKey) ?? false;
  }

  Future<void> setPopupNotifRequested(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_popupNotifRequestedKey, v);
  }
}
