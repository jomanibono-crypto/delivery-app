import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'local_storage_service.dart';
import 'alert_service.dart';
import 'voice_service.dart';

/// Handles local notifications for proximity alerts.
///
/// PART 2 + PART 3: The channel ID is VERSIONED. Android channels are immutable
/// once created, so every time the user picks a new sound we increment the
/// version and build a fresh channel. This ensures the new sound + MAX priority
/// take effect immediately. The version persists across restarts.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  FlutterLocalNotificationsPlugin get plugin => _plugin;
  final LocalStorageService _storage = LocalStorageService();

  /// The currently-active channel id (e.g. 'proximity_channel_v3').
  /// Computed at initialize() from the persisted version.
  String _activeChannelId = 'proximity_channel_v3';
  String get activeChannelId => _activeChannelId;

  /// All channel IDs ever used (for cleanup). We delete the previous one on
  /// each change so stale channels don't linger in system settings.
  static const List<String> _legacyChannelIds = [
    'proximity_channel',
    'proximity_channel_v2',
  ];

  bool _initialized = false;

  /// Initialize notification channels and plugin.
  Future<void> initialize() async {
    if (_initialized) {
      debugPrint('[Notif] Already initialized — skipping.');
      return;
    }
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    final ok = await _plugin.initialize(settings);
    _initialized = true;
    debugPrint('[Notif] Initialized. ok=$ok');

    // Clean up legacy channels, then create the versioned channel for the
    // currently-saved sound.
    await _deleteLegacyChannels();
    await _recreateChannel();
  }

  /// Delete all known legacy channel IDs.
  Future<void> _deleteLegacyChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    for (final id in _legacyChannelIds) {
      try {
        await android.deleteNotificationChannel(id);
      } catch (_) {}
    }
    // Also delete the previous active channel if it differs from current.
    // We'll re-create prevId below, so don't delete it here.
  }

  /// Build a fresh channel with the current sound + MAX priority.
  /// Called on app start AND whenever the user changes the sound.
  Future<void> _recreateChannel({bool bumpVersion = false}) async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    int ver = await _storage.getChannelVersion();
    if (bumpVersion) {
      // Delete the current channel before incrementing.
      final oldId = 'proximity_channel_v$ver';
      try {
        await android.deleteNotificationChannel(oldId);
        debugPrint('[Notif] Deleted old channel "$oldId".');
      } catch (_) {}
      ver += 1;
      await _storage.setChannelVersion(ver);
    }

    _activeChannelId = 'proximity_channel_v$ver';
    final soundKey = await _storage.getNotifSound();

    // Resolve the sound resource for this selection.
    final AndroidNotificationSound? sound = _resolveSound(soundKey);
    final bool playSound = soundKey != 'silent';

    final channel = AndroidNotificationChannel(
      _activeChannelId,
      'Proximity Alerts',
      description: 'Notifications when group members are nearby',
      // PART 3: MAX importance → triggers heads-up banner over other apps.
      importance: Importance.max,
      playSound: playSound,
      sound: sound,
      enableVibration: playSound,
      vibrationPattern: Int64List.fromList([0, 300, 200, 300]),
      showBadge: true,
    );
    await android.createNotificationChannel(channel);
    debugPrint(
      '[Notif] Channel "$_activeChannelId" created '
      '(sound=$soundKey, playSound=$playSound, importance=max).',
    );
  }

  /// Map a sound-key to the platform sound reference.
  /// 'default' → null lets Android use the system default notification sound.
  /// 'chime1/2/3' → bundled WAV in res/raw/.
  /// 'silent' → null + playSound=false.
  AndroidNotificationSound? _resolveSound(String key) {
    switch (key) {
      case 'chime1':
        return const RawResourceAndroidNotificationSound('chime1');
      case 'chime2':
        return const RawResourceAndroidNotificationSound('chime2');
      case 'chime3':
        return const RawResourceAndroidNotificationSound('chime3');
      case 'default':
      case 'silent':
      default:
        // null = Android uses the system default sound on the channel.
        // For 'silent' we set playSound=false separately.
        return null;
    }
  }

  /// PART 2: called when the user picks a new sound in settings.
  /// Saves the choice, recreates the channel with a bumped version, and
  /// plays a preview.
  Future<void> changeSound(String soundKey) async {
    await _storage.setNotifSound(soundKey);
    await _recreateChannel(bumpVersion: true);
    // Preview: show a test notification so the user hears it immediately.
    await showProximityNotification('معاينة الصوت', 100);
  }

  /// Play a brief preview of the given sound without bumping the channel
  /// version or changing the saved preference.
  Future<void> previewSound(String soundKey) async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    final sound = _resolveSound(soundKey);
    final playSound = soundKey != 'silent';

    const previewId = 'sound_preview_channel';
    try {
      await android.deleteNotificationChannel(previewId);
    } catch (_) {}

    final channel = AndroidNotificationChannel(
      previewId,
      'Sound Preview',
      description: 'Temporary channel for sound preview',
      importance: Importance.max,
      playSound: playSound,
      sound: sound,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 200, 100, 200]),
    );
    await android.createNotificationChannel(channel);

    await _plugin.show(
      999999,
      'معاينة الصوت',
      '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          previewId,
          'Sound Preview',
          importance: Importance.max,
          priority: Priority.max,
          playSound: playSound,
          sound: sound,
          enableVibration: true,
          autoCancel: true,
        ),
      ),
    );

    Future.delayed(const Duration(milliseconds: 1500), () {
      _plugin.cancel(999999);
    });
  }

  /// Send a test notification using current settings (sound, vibration, TTS).
  Future<void> sendTestNotification({
    bool playSound = true,
    bool enableVibration = true,
    bool enableVoice = false,
  }) async {
    final soundKey = await _storage.getNotifSound();
    final shouldPlaySound = playSound && soundKey != 'silent';

    final vibePattern = enableVibration
        ? Int64List.fromList([0, 300, 200, 300, 200, 300])
        : null;

    await _plugin.show(
      888888,
      '🔔 اختبار الإشعار',
      'هذا إشعار اختباري — تم إرساله من الإعدادات',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _activeChannelId,
          'Proximity Alerts',
          channelDescription: 'Notifications when group members are nearby',
          importance: Importance.max,
          priority: Priority.max,
          playSound: shouldPlaySound,
          enableVibration: enableVibration,
          vibrationPattern: vibePattern,
          fullScreenIntent: false,
          visibility: NotificationVisibility.public,
          autoCancel: true,
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );

    if (enableVibration) {
      HapticFeedback.heavyImpact();
    }

    if (enableVoice) {
      try {
        VoiceService().speak('هذا اختبار للإشعارات');
      } catch (_) {}
    }
  }

  /// Request notification permissions (needed for Android 13+).
  Future<bool> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final granted = await android?.requestNotificationsPermission() ?? false;
    debugPrint('[Notif] Permission granted=$granted');
    return granted;
  }

  /// Show a proximity notification when a member is nearby.
  ///
  /// PART 3: MAX priority + high visibility → appears as a heads-up banner
  /// over other apps (WhatsApp, YouTube, etc.) when the app is backgrounded.
  Future<void> showProximityNotification(
    String memberName,
    double distance,
  ) async {
    final soundKey = await _storage.getNotifSound();
    final bool playSound = soundKey != 'silent';

    final androidDetails = AndroidNotificationDetails(
      _activeChannelId,
      'Proximity Alerts',
      channelDescription: 'Notifications when group members are nearby',
      // PART 3: MAX priority for heads-up display.
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      playSound: playSound,
      enableVibration: playSound,
      // PART 3: banner only, not full-screen takeover.
      fullScreenIntent: false,
      visibility: NotificationVisibility.public,
      // Keep the notification from grouping/being suppressed.
      autoCancel: true,
      category: AndroidNotificationCategory.alarm,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final distanceFormatted = distance < 1000
        ? '${distance.toStringAsFixed(0)}م'
        : '${(distance / 1000).toStringAsFixed(1)}كم';

    debugPrint(
      '[Notif] SHOW proximity: member=$memberName dist=$distanceFormatted '
      '(channel=$_activeChannelId, sound=$soundKey)',
    );

    await _plugin.show(
      memberName.hashCode, // Unique ID per member
      '🔴 صاحبك قريب!',
      '$memberName قريب منك! المسافة: $distanceFormatted',
      details,
    );
  }

  /// Show a notification for a new chat message.
  ///
  /// Uses a different notification ID than proximity so both can coexist.
  Future<void> showChatMessageNotification({
    required String senderName,
    required String message,
    String? senderIcon,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _activeChannelId,
      'Proximity Alerts',
      channelDescription: 'Notifications when group members are nearby',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      visibility: NotificationVisibility.public,
      autoCancel: true,
      category: AndroidNotificationCategory.message,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final title = '📩 $senderName';

    debugPrint('[Notif] SHOW chat message from "$senderName": "$message"');

    // Use a unique ID per sender so new messages replace old ones for same sender.
    await _plugin.show(2000 + senderName.hashCode, title, message, details);
  }

  /// Show a notification when a new alert (police/radar/control) appears.
  Future<void> showAlertNotification(AlertData alert) async {
    final androidDetails = AndroidNotificationDetails(
      _activeChannelId,
      'Proximity Alerts',
      channelDescription: 'Notifications when group members are nearby',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      visibility: NotificationVisibility.public,
      autoCancel: true,
      category: AndroidNotificationCategory.alarm,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final latStr = alert.lat.toStringAsFixed(4);
    final lngStr = alert.lng.toStringAsFixed(4);

    await _plugin.show(
      4000 + alert.id.hashCode,
      '${alert.type.label} في منطقتك!',
      'أبلغ ${alert.userName} عن ${alert.type.label} — اضغط لفتح الخريطة\n$latStr, $lngStr',
      details,
    );
  }
}
