import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/health_service.dart';

class HealthDashboard extends StatefulWidget {
  final String? groupCode;
  final Map<String, Map<String, dynamic>>? members;
  final double? mapZoom;
  final String? mapCenter;
  final int? loadedMarkers;
  final bool? mapReady;
  final bool? tilesLoaded;

  const HealthDashboard({
    super.key,
    this.groupCode,
    this.members,
    this.mapZoom,
    this.mapCenter,
    this.loadedMarkers,
    this.mapReady,
    this.tilesLoaded,
  });

  @override
  State<HealthDashboard> createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<HealthDashboard> {
  final HealthService _health = HealthService();
  HealthReport? _report;
  Map<String, String>? _diagnosticResults;
  bool _loading = true;
  bool _diagnosticRunning = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final report = await _health.collectReport(
      groupCode: widget.groupCode,
      members: widget.members,
      mapZoom: widget.mapZoom,
      mapCenter: widget.mapCenter,
      loadedMarkerCount: widget.loadedMarkers,
      mapIsReady: widget.mapReady,
      tilesAreLoaded: widget.tilesLoaded,
    );
    if (mounted) setState(() { _report = report; _loading = false; });
  }

  Future<void> _runDiagnostic() async {
    setState(() => _diagnosticRunning = true);
    final results = await _health.runFullDiagnostic();
    if (mounted) setState(() { _diagnosticResults = results; _diagnosticRunning = false; });
  }

  Color _statusColor(HealthStatus status) {
    switch (status) {
      case HealthStatus.ok:
        return const Color(0xFF4CAF50);
      case HealthStatus.warning:
        return const Color(0xFFFF9800);
      case HealthStatus.error:
        return const Color(0xFFE53935);
    }
  }

  Widget _statusDot(HealthStatus status) {
    return Container(
      width: 12, height: 12,
      decoration: BoxDecoration(color: _statusColor(status), shape: BoxShape.circle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _report;

    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.monitor_heart_rounded, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('لوحة الصحة'),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _refresh),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Live Status Cards ──
                _buildSectionHeader(context, 'حالة الخدمات'),
                _statusRow('GPS', r!.gpsStatus),
                _statusRow('الإنترنت', r.internetStatus),
                _statusRow('Firebase', r.firebaseStatus),
                _statusRow('الخلفية', r.backgroundServiceStatus),
                _statusRow('الإشعارات', r.notificationStatus),
                _statusRow('الاهتزاز', r.vibrationAvailable ? HealthStatus.ok : HealthStatus.warning),
                _statusRow('الخريطة', r.mapStatus),
                _statusRow('التحديثات', r.autoUpdateStatus),

                const SizedBox(height: 24),

                // ── GPS ──
                _buildSectionHeader(context, 'GPS'),
                _card(context, [
                  _row('خط العرض', r.latitude?.toStringAsFixed(4) ?? 'غير معروف'),
                  _row('خط الطول', r.longitude?.toStringAsFixed(4) ?? 'غير معروف'),
                  _row('الدقة', r.accuracy?.toStringAsFixed(1) ?? '—'),
                  _row('السرعة', r.speed?.toStringAsFixed(1) ?? '—'),
                  _row('الاتجاه', r.heading?.toStringAsFixed(1) ?? '—'),
                  _row('الارتفاع', r.altitude?.toStringAsFixed(1) ?? '—'),
                  _row('خدمة الموقع', r.locationServiceEnabled ? 'مفعلة' : 'معطلة'),
                  _row('الإذن', r.permissionState?.name ?? '—'),
                  _row('الخلفية', r.backgroundLocationGranted ? 'مسموح' : 'غير مسموح'),
                  _row('آخر تحديث', r.lastGpsUpdate?.toIso8601String().substring(11, 19) ?? '—'),
                ]),

                const SizedBox(height: 16),

                // ── Network ──
                _buildSectionHeader(context, 'الشبكة'),
                _card(context, [
                  _row('الحالة', r.internetConnected ? 'متصل' : 'غير متصل'),
                  _row('زمن الاستجابة', r.pingLatencyMs != null ? '${r.pingLatencyMs}ms' : '—'),
                  _row('النوع', r.networkType ?? '—'),
                ]),

                const SizedBox(height: 16),

                // ── Firebase ──
                _buildSectionHeader(context, 'Firebase'),
                _card(context, [
                  _row('المصادقة', r.firebaseAuthenticated ? 'نعم' : 'لا'),
                  _row('المعرف', r.firebaseAuthUserId?.substring(0, 8) ?? '—'),
                  _row('قاعدة البيانات', r.databaseConnected ? 'متصل' : 'غير متصل'),
                  _row('آخر كتابة', r.lastFirebaseWriteSuccess ? 'نجاح' : 'فشل'),
                  _row('آخر قراءة', r.lastFirebaseReadSuccess ? 'نجاح' : 'فشل'),
                ]),

                const SizedBox(height: 16),

                // ── Group ──
                _buildSectionHeader(context, 'المجموعة'),
                _card(context, [
                  _row('الأعضاء المتصلون', '${r.membersOnline}'),
                  _row('الأعضاء غير المتصلين', '${r.membersOffline}'),
                  _row('كود المجموعة', r.groupId ?? '—'),
                ]),

                const SizedBox(height: 16),

                // ── Map ──
                _buildSectionHeader(context, 'الخريطة'),
                _card(context, [
                  _row('التكبير', '${r.currentZoom}'),
                  _row('الموقع', r.cameraPosition ?? '—'),
                  _row('العلامات المحملة', '${r.loadedMarkers}'),
                  _row('الخريطة جاهزة', r.mapReady ? 'نعم' : 'لا'),
                  _row('البلاط محمل', r.tilesLoaded ? 'نعم' : 'لا'),
                ]),

                const SizedBox(height: 16),

                // ── Alerts ──
                _buildSectionHeader(context, 'البلاغات'),
                _card(context, [
                  _row('شرطة', '${r.policeAlerts}'),
                  _row('رادار', '${r.radarAlerts}'),
                  _row('مراقب', '${r.inspectorAlerts}'),
                  _row('خطر', '${r.hazardAlerts}'),
                  _row('حادث', '${r.accidentAlerts}'),
                  _row('عميل سيء', '${r.badCustomerAlerts}'),
                ]),

                const SizedBox(height: 16),

                // ── System ──
                _buildSectionHeader(context, 'النظام'),
                _card(context, [
                  _row('الإصدار', 'v${r.appVersion}'),
                  _row('رقم البناء', '${r.buildNumber}'),
                  _row('الجهاز', r.deviceModel ?? '—'),
                  _row('أندرويد', r.androidVersion ?? '—'),
                ]),

                const SizedBox(height: 24),

                // ── Diagnostics ──
                _buildSectionHeader(context, 'التشخيص'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    _diagButton('فحص GPS', () => _runSingleTest('GPS', () => _health.runGpsTest())),
                    _diagButton('فحص Firebase', () => _runSingleTest('Firebase', () => _health.runFirebaseTest())),
                    _diagButton('فحص الإنترنت', () => _runSingleTest('الإنترنت', () => _health.runInternetTest())),
                    _diagButton('فحص الإشعارات', () => _runSingleTest('الإشعارات', () => _health.runNotificationTest())),
                    _diagButton('فحص الاهتزاز', () => _runSingleTest('الاهتزاز', () => _health.runVibrationTest())),
                    _diagButton('فحص التحديثات', () => _runSingleTest('التحديثات', () => _health.runAutoUpdateTest())),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _diagnosticRunning ? null : _runDiagnostic,
                    icon: _diagnosticRunning
                        ? SizedBox(width: 18, height: 18, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.checklist_rounded),
                    label: Text(_diagnosticRunning ? 'جارٍ التشخيص...' : 'تشخيص كامل'),
                  ),
                ),

                if (_diagnosticResults != null) ...[
                  const SizedBox(height: 16),
                  _buildSectionHeader(context, 'نتائج التشخيص'),
                  _card(context, _diagnosticResults!.entries.map((e) =>
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(flex: 2, child: Text(e.key, style: theme.textTheme.bodyMedium)),
                          const SizedBox(width: 8),
                          Expanded(flex: 3, child: Text(e.value, style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ),
                  ).toList()),
                ],

                const SizedBox(height: 12),

                // Export button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _report == null ? null : () => _exportReport(context),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('تصدير التقرير'),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(width: 3, height: 18,
          decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
      ]),
    );
  }

  Widget _statusRow(String label, HealthStatus status) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          _statusDot(status),
          const SizedBox(width: 12),
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Text(
            status == HealthStatus.ok ? 'يعمل' : status == HealthStatus.warning ? 'تحذير' : 'خطأ',
            style: TextStyle(
              color: _statusColor(status), fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }

  Widget _row(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 2, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        Expanded(flex: 2, child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.end)),
      ]),
    );
  }

  Widget _diagButton(String label, VoidCallback onPressed) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onPressed,
    );
  }

  Future<void> _runSingleTest(String name, Future<String> Function() test) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('جاري فحص $name...'),
      duration: const Duration(seconds: 1),
    ));
    final result = await test();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result),
        duration: const Duration(seconds: 3),
        backgroundColor: result.startsWith('✅') ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
      ));
    }
  }

  void _exportReport(BuildContext context) {
    final r = _report;
    if (r == null) return;

    final buffer = StringBuffer();
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('  HEALTH REPORT — GlovoMate');
    buffer.writeln('  ${DateTime.now().toIso8601String()}');
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('');
    buffer.writeln('الإصدار: v${r.appVersion}+${r.buildNumber}');
    buffer.writeln('الجهاز: ${r.deviceModel ?? '—'}');
    buffer.writeln('أندرويد: ${r.androidVersion ?? '—'}');
    buffer.writeln('');
    buffer.writeln('── GPS ──');
    buffer.writeln('الحالة: ${r.locationServiceEnabled ? 'مفعل' : 'معطل'}');
    buffer.writeln('الموقع: ${r.latitude?.toStringAsFixed(4) ?? '—'}, ${r.longitude?.toStringAsFixed(4) ?? '—'}');
    buffer.writeln('');
    buffer.writeln('── الشبكة ──');
    buffer.writeln('الحالة: ${r.internetConnected ? 'متصل' : 'غير متصل'}');
    buffer.writeln('زمن الاستجابة: ${r.pingLatencyMs ?? '—'}ms');
    buffer.writeln('');
    buffer.writeln('── Firebase ──');
    buffer.writeln('المصادقة: ${r.firebaseAuthenticated ? 'نعم' : 'لا'}');
    buffer.writeln('قاعدة البيانات: ${r.databaseConnected ? 'متصل' : 'غير متصل'}');
    buffer.writeln('');
    buffer.writeln('── الخدمات ──');
    buffer.writeln('GPS: ${r.locationServiceEnabled ? '✅' : '❌'}');
    buffer.writeln('الإنترنت: ${r.internetConnected ? '✅' : '❌'}');
    buffer.writeln('Firebase: ${r.firebaseAuthenticated ? '✅' : '❌'}');
    buffer.writeln('الخريطة: ${r.mapReady ? '✅' : '❌'}');
    buffer.writeln('الإشعارات: ${r.notificationsEnabled ? '✅' : '⚠️'}');
    buffer.writeln('');
    buffer.writeln('── المجموعة ──');
    buffer.writeln('المعرف: ${r.groupId ?? '—'}');
    buffer.writeln('متصل: ${r.membersOnline} | غير متصل: ${r.membersOffline}');
    buffer.writeln('');
    buffer.writeln('═══════════════════════════════════════');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('تم نسخ التقرير إلى الحافظة'),
      backgroundColor: Color(0xFF2E7D32),
    ));
  }
}
