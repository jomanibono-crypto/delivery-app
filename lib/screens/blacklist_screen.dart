import 'dart:async';
import 'package:flutter/material.dart';
import '../services/blacklist_service.dart';
import '../services/foreground_screen_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_bottom_nav.dart';
import 'map_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class BlacklistScreen extends StatefulWidget {
  final String groupCode;
  final String userName;

  const BlacklistScreen({
    super.key,
    required this.groupCode,
    required this.userName,
  });

  @override
  State<BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends State<BlacklistScreen> {
  final BlacklistService _service = BlacklistService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  StreamSubscription<List<BlacklistEntry>>? _subscription;
  List<BlacklistEntry> _entries = [];
  List<BlacklistEntry> _filteredEntries = [];
  BlacklistEntry? _found;

  @override
  void initState() {
    super.initState();
    ForegroundScreenService().set(ForegroundScreen.blacklist);
    _subscription = _service.watchAll().listen((entries) {
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _applyFilter();
      });
    });
  }

  @override
  void dispose() {
    ForegroundScreenService().clear(ForegroundScreen.blacklist);
    _subscription?.cancel();
    _searchController.dispose();
    _phoneController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      _filteredEntries = _entries;
      _found = null;
    } else {
      final normalized = BlacklistService.normalize(q);
      _found = _entries.where((e) => e.normalized == normalized).firstOrNull;
      _filteredEntries = _entries
          .where(
            (e) =>
                e.phone.contains(q) ||
                e.reason.contains(q) ||
                e.addedByName.contains(q),
          )
          .toList();
    }
  }

  void _showAddDialog() {
    final theme = Theme.of(context);
    _phoneController.clear();
    _reasonController.clear();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.person_off_rounded,
                  color: theme.colorScheme.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'إضافة إلى القائمة السوداء',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _phoneController,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'رقم الهاتف',
                  hintText: 'مثال: +212612345678 أو 0612345678',
                  prefixIcon: const Icon(Icons.phone_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reasonController,
                textDirection: TextDirection.rtl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'سبب الإضافة',
                  hintText: 'اكتب سبب إضافة الرقم...',
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () {
                final phone = _phoneController.text.trim();
                final reason = _reasonController.text.trim();
                if (phone.isEmpty) return;
                Navigator.pop(ctx);
                _service.addEntry(phone: phone, reason: reason);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BlacklistEntry entry) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: theme.colorScheme.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text('هل أنت متأكد؟', style: theme.textTheme.titleLarge),
            ],
          ),
          content: Text(
            'سيتم حذف الرقم ${entry.phone} من القائمة السوداء',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('لا'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _service.deleteEntry(entry.id);
              },
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
              ),
              child: const Text('نعم، احذف'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Column(
              children: [
                if (_found != null) _buildFoundCard(),
                if (_entries.isNotEmpty) _buildStatsCard(),
                Expanded(
                  child: _filteredEntries.isEmpty
                      ? _buildEmptyState()
                      : _buildList(),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: AppColors.indigo500,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: Text('إضافة', style: AppTypography.buttonMd.copyWith(color: Colors.white)),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.rose500, Color(0xFFC73050)],
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(
                      Icons.block_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'القائمة السوداء',
                          style: AppTypography.titleLg,
                        ),
                        Text(
                          '${_entries.length} رقم محظور',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.ink500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.ink50,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: TextField(
                  controller: _searchController,
                  textDirection: TextDirection.rtl,
                  style: AppTypography.bodyLg,
                  decoration: InputDecoration(
                    hintText: 'ابحث برقم الهاتف أو الاسم...',
                    hintStyle: AppTypography.bodyMd.copyWith(
                      color: AppColors.ink400,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.ink500,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear_rounded,
                              color: AppColors.ink500,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _applyFilter());
                            },
                          )
                        : null,
                    filled: false,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                  ),
                  onChanged: (_) => setState(() => _applyFilter()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFoundCard() {
    final found = _found!;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.danger.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'هذا الرقم موجود في القائمة السوداء!',
                  style: AppTypography.titleSm.copyWith(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'رقم: ${found.phone}',
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (found.reason.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'سبب: ${found.reason}',
                    style: AppTypography.bodySm,
                  ),
                ],
                Text(
                  'أضيف بواسطة: ${found.addedByName}',
                  style: AppTypography.labelSm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.dangerGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppColors.shadowGlowDanger,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_entries.length}',
                style: AppTypography.numberXl.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                'رقم محظور في القائمة',
                style: AppTypography.bodySm.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.rose500, Color(0xFFC73050)],
                ),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              _searchController.text.isEmpty
                  ? 'القائمة السوداء فارغة'
                  : 'لا توجد نتائج',
              style: AppTypography.titleLg,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _searchController.text.isEmpty
                  ? 'أضف أرقاماً مزعجة لتجنبها'
                  : 'جرّب كلمة بحث أخرى',
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.ink500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.huge * 2,
      ),
      itemCount: _filteredEntries.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (ctx, i) {
        final entry = _filteredEntries[i];
        return _BlacklistCard(
          entry: entry,
          onDelete: () => _confirmDelete(entry),
        );
      },
    );
  }

  Widget _buildBottomNav() {
    return AppBottomNav(
      selectedIndex: 2,
      onDestinationSelected: (index) {
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MapScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        } else if (index == 1) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        } else if (index == 3) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        }
      },
    );
  }
}

class _BlacklistCard extends StatelessWidget {
  final BlacklistEntry entry;
  final VoidCallback onDelete;
  const _BlacklistCard({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.ink100),
        boxShadow: AppColors.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.rose500.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.person_off_rounded,
              color: AppColors.rose500,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.phone,
                  style: AppTypography.titleSm.copyWith(
                    fontFamily: 'monospace',
                  ),
                  textDirection: TextDirection.ltr,
                ),
                if (entry.reason.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.reason,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.ink500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  'بواسطة: ${entry.addedByName}',
                  style: AppTypography.labelSm,
                ),
              ],
            ),
          ),
          Material(
            color: AppColors.rose500.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.rose500,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
