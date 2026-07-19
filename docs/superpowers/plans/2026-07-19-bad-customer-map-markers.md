# Persistent "Bad Customer" Map Markers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let drivers long-press the map to drop a small, persistent red marker labeled "زبون سيئ" that never disappears until manually deleted.

**Architecture:** Extend the existing `BlacklistEntry` model with nullable `lat`/`lng`/`name`. A new `MarkerLayer` on the map is driven by a `ValueNotifier<List<BlacklistEntry>>` subscribed to a new `BlacklistService.watchMarkers()` stream. The long-press context menu gains a "permanent markers" section that opens an add-composer sheet. Tapping a marker opens a detail sheet with a delete button. The Firebase `blacklist` node has no TTL, so persistence is automatic.

**Tech Stack:** Flutter, `flutter_map` ^8.1.0 (Flutter-widget markers), `firebase_database`, existing `AppBottomSheet` / `AppInput` / `AppButton` / `InfoRow` widgets.

**Reference spec:** `docs/superpowers/specs/2026-07-19-bad-customer-map-markers-design.md`

**Branch:** `feat/bad-customer-markers` (already created)

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `lib/services/blacklist_service.dart` | Data model + Firebase CRUD | Extend `BlacklistEntry`, extend `addEntry`, add `watchMarkers` |
| `lib/screens/map_screen.dart` | Map UI + interaction | New notifier + subscription, new `MarkerLayer`, long-press menu section, add-composer sheet, detail sheet |
| `pubspec.yaml` | Version | Bump to `1.9.4+46` |
| `CHANGELOG.md` | Release notes | Add `1.9.4+46` entry |

No new files — everything extends existing code. The `blacklist_screen.dart` is NOT touched (its existing entries still render fine; entries with `lat` simply have `lat != null` but the list view is unchanged — out of scope per spec).

---

## Task 1: Extend `BlacklistEntry` model with location fields

**Files:**
- Modify: `lib/services/blacklist_service.dart:6-36`

- [ ] **Step 1: Add `lat`, `lng`, `name` fields to `BlacklistEntry`**

Replace lines 6-36 (the entire `BlacklistEntry` class) with:

```dart
class BlacklistEntry {
  final String id;
  final String phone;
  final String normalized;
  final String reason;
  final String addedBy;
  final String addedByName;
  final int timestamp;
  /// Location of a persistent map marker. `null` for phone-only entries.
  final double? lat;
  /// Location of a persistent map marker. `null` for phone-only entries.
  final double? lng;
  /// Optional customer name shown on a map marker detail sheet.
  final String? name;

  BlacklistEntry({
    required this.id,
    required this.phone,
    required this.normalized,
    required this.reason,
    required this.addedBy,
    required this.addedByName,
    required this.timestamp,
    this.lat,
    this.lng,
    this.name,
  });

  /// True when this entry should render as a map marker.
  bool get hasMarker => lat != null && lng != null;

  factory BlacklistEntry.fromMap(Map<dynamic, dynamic> map, String id) {
    return BlacklistEntry(
      id: id,
      phone: map['phone'] as String? ?? '',
      normalized: map['normalized'] as String? ?? '',
      reason: map['reason'] as String? ?? '',
      addedBy: map['addedBy'] as String? ?? '',
      addedByName: map['addedByName'] as String? ?? 'عضو',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      name: map['name'] as String?,
    );
  }
}
```

Note: `addedByName` default changed from `''` to `'عضو'` to match the `addEntry` fallback (line 56). Old data with missing `addedByName` previously deserialized as `''`; it now becomes `'عضو'`. This is a small improvement for display only.

- [ ] **Step 2: Verify it compiles**

Run: `cd D:/glovo_mate && flutter analyze lib/services/blacklist_service.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd D:/glovo_mate
git add lib/services/blacklist_service.dart
git commit -m "feat(blacklist): add lat/lng/name to BlacklistEntry model"
```

---

## Task 2: Extend `BlacklistService.addEntry` and add `watchMarkers`

**Files:**
- Modify: `lib/services/blacklist_service.dart:53-66` (addEntry) and `:88-102` (after watchAll)

- [ ] **Step 1: Make `addEntry` accept optional lat/lng/name and optional phone/reason**

Replace the existing `addEntry` (lines 53-66) with:

```dart
  /// Add an entry. Either a phone-only block (legacy) or a map marker
  /// (when `lat`/`lng` are provided). `phone` and `reason` are optional in
  /// both cases; a pure marker may carry no phone at all.
  Future<void> addEntry({
    String? phone,
    String? reason,
    double? lat,
    double? lng,
    String? name,
  }) async {
    await _firebase.signInAnonymously();
    final uid = _firebase.userId;
    final userName = _firebase.currentUser?.displayName ?? 'عضو';
    final ref = _db.child('blacklist').push();
    final data = <String, dynamic>{
      'addedBy': uid,
      'addedByName': userName,
      'timestamp': ServerValue.timestamp,
    };
    if (phone != null && phone.trim().isNotEmpty) {
      data['phone'] = phone.trim();
      data['normalized'] = normalize(phone);
    } else {
      data['phone'] = '';
      data['normalized'] = '';
    }
    if (reason != null && reason.trim().isNotEmpty) {
      data['reason'] = reason.trim();
    } else {
      data['reason'] = '';
    }
    if (lat != null) data['lat'] = lat;
    if (lng != null) data['lng'] = lng;
    if (name != null && name.trim().isNotEmpty) data['name'] = name.trim();
    await ref.set(data);
  }
```

- [ ] **Step 2: Add `watchMarkers()` after `watchAll()` (after line 102)**

Append this method to the `BlacklistService` class, just before the closing `}` of the class (currently line 103):

```dart
  /// Stream of entries that have a map location (persistent markers).
  /// Phone-only entries (no lat/lng) are filtered out.
  Stream<List<BlacklistEntry>> watchMarkers() {
    return watchAll().map((entries) => entries.where((e) => e.hasMarker).toList());
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `cd D:/glovo_mate && flutter analyze lib/services/blacklist_service.dart`
Expected: `No issues found!`

- [ ] **Step 4: Check for broken call-sites**

Run: `cd D:/glovo_mate && grep -rn "addEntry(" lib/`
Expected output: only `blacklist_screen.dart` (calls with named `phone:` and `reason:` — those are now optional but the existing call still compiles since it passes both). And the method definition itself.

Verify the existing call in `blacklist_screen.dart` still compiles — `addEntry(phone: ..., reason: ...)` is valid against the new signature because both are optional named params.

Run: `cd D:/glovo_mate && flutter analyze lib/`
Expected: `No issues found!` (or only pre-existing warnings unrelated to this change).

- [ ] **Step 5: Commit**

```bash
cd D:/glovo_mate
git add lib/services/blacklist_service.dart
git commit -m "feat(blacklist): support location-based entries and watchMarkers()"
```

---

## Task 3: Add the marker notifier, subscription, and dispose in `MapScreen`

**Files:**
- Modify: `lib/screens/map_screen.dart`
  - Imports (around line 1-26)
  - Service field (around line 47)
  - Subscription field (around line 52)
  - Notifier field (around line 76-77)
  - `dispose()` (around line 116-117)
  - `_initSequence()` (around line 173)

- [ ] **Step 1: Add the `BlacklistService` import**

In the import block at the top of `lib/screens/map_screen.dart`, after line 14 (`import '../services/map_cache_service.dart';`), add:

```dart
import '../services/blacklist_service.dart';
```

(Insert it alphabetically among the service imports — anywhere in that block is fine.)

- [ ] **Step 2: Add the `_blacklistSvc` service field**

After line 47 (`final AlertService _alertSvc = AlertService();`), add:

```dart
  final BlacklistService _blacklistSvc = BlacklistService();
```

- [ ] **Step 3: Add the subscription field**

After line 53 (`StreamSubscription<List<AlertData>>? _alertsSub;`), add:

```dart
  StreamSubscription<List<BlacklistEntry>>? _badCustomerSub;
```

- [ ] **Step 4: Add the notifier**

After line 77 (the `_alertsNotifier` definition, which ends at line 77), add:

```dart
  final ValueNotifier<List<BlacklistEntry>> _badCustomerNotifier =
      ValueNotifier([]);
  List<BlacklistEntry> get _badCustomers => _badCustomerNotifier.value;
```

- [ ] **Step 5: Cancel the subscription in `dispose()`**

After line 117 (`_alertsSub?.cancel();`), add:

```dart
    _badCustomerSub?.cancel();
```

- [ ] **Step 6: Add a `_listenBadCustomers()` method and call it**

After the `_listenAlerts()` method (which ends at line 232), add a new method:

```dart
  void _listenBadCustomers() {
    _badCustomerSub = _blacklistSvc.watchMarkers().listen((entries) {
      if (!mounted) return;
      _badCustomerNotifier.value = entries;
    }, onError: (e) {
      debugPrint('[Map] Bad-customer marker stream error: $e');
    });
  }
```

Then in `_initSequence()`, after line 173 (`debugPrint('[Map] Alert listener started');`), add:

```dart
      _listenBadCustomers();
      debugPrint('[Map] Bad-customer listener started');
```

- [ ] **Step 7: Verify it compiles**

Run: `cd D:/glovo_mate && flutter analyze lib/screens/map_screen.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
cd D:/glovo_mate
git add lib/screens/map_screen.dart
git commit -m "feat(map): subscribe to bad-customer markers"
```

---

## Task 4: Render the marker layer and marker widgets

**Files:**
- Modify: `lib/screens/map_screen.dart`
  - `FlutterMap.children` (around line 926-937)
  - Add `_buildBadCustomerMarkers()` method near `_buildAlertMarkers()` (line 612)

- [ ] **Step 1: Add the new `MarkerLayer` to the map's children**

In the `FlutterMap` `children:` list, after the alerts `ValueListenableBuilder` block (which ends at line 931 with `),`) and before the members `ValueListenableBuilder` block (line 932), insert:

```dart
            ValueListenableBuilder<List<BlacklistEntry>>(
              valueListenable: _badCustomerNotifier,
              builder: (_, entries, _) => MarkerLayer(
                markers: _buildBadCustomerMarkers(),
              ),
            ),
```

- [ ] **Step 2: Add the `_buildBadCustomerMarkers()` method**

After the `_buildAlertMarkers()` method (which ends at line 681 with `}`), add:

```dart
  List<Marker> _buildBadCustomerMarkers() {
    return _badCustomers.map((entry) {
      return Marker(
        point: LatLng(entry.lat!, entry.lng!),
        width: 110,
        height: 70,
        child: GestureDetector(
          onTap: () => _showBadCustomerDetail(entry),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.dangerGradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_off_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'زبون سيئ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `cd D:/glovo_mate && flutter analyze lib/screens/map_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd D:/glovo_mate
git add lib/screens/map_screen.dart
git commit -m "feat(map): render persistent bad-customer markers"
```

---

## Task 5: Add the marker detail sheet + delete

**Files:**
- Modify: `lib/screens/map_screen.dart`
  - Add `_showBadCustomerDetail()` and `_confirmDeleteBadCustomer()` methods (place them right after `_showAlertContextMenu`, ~line 430)

- [ ] **Step 1: Add imports for AppButton, AppInput, InfoRow if not present**

Check current imports of `map_screen.dart`. They already include `app_bottom_sheet.dart` (line 21). We need `app_button.dart`, `app_input.dart`, and `info_row.dart`. Add these imports (anywhere in the existing widget-import block, lines 11-21):

```dart
import '../widgets/app_button.dart';
import '../widgets/app_input.dart';
import '../widgets/info_row.dart';
```

- [ ] **Step 2: Add the `_showBadCustomerDetail()` method**

After the `_showAlertContextMenu` method (which ends at line 430 with `}`), add:

```dart
  /// Detail sheet for a persistent bad-customer marker. Shows whatever
  /// metadata the entry carries and a delete button.
  void _showBadCustomerDetail(BlacklistEntry entry) {
    AppBottomSheet.show<void>(
      context,
      title: 'زبون سيئ',
      subtitle: 'علامة دائمة على الخريطة',
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                gradient: AppColors.dangerGradient,
                shape: BoxShape.circle,
                boxShadow: AppColors.shadowGlowDanger,
              ),
              child: const Icon(
                Icons.person_off_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (entry.name != null && entry.name!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: InfoRow(
                icon: Icons.person_rounded,
                label: 'الاسم',
                value: entry.name!,
              ),
            ),
          if (entry.phone.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: InfoRow(
                icon: Icons.phone_rounded,
                label: 'الهاتف',
                value: entry.phone,
              ),
            ),
          if (entry.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: InfoRow(
                icon: Icons.note_rounded,
                label: 'السبب',
                value: entry.reason,
              ),
            ),
          InfoRow(
            icon: Icons.person_pin_rounded,
            label: 'أضيفت بواسطة',
            value: entry.addedByName,
          ),
          if (entry.timestamp > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            InfoRow(
              icon: Icons.schedule_rounded,
              label: 'التاريخ',
              value: relativeTime(entry.timestamp),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'حذف العلامة',
            variant: AppButtonVariant.danger,
            leadingIcon: Icons.delete_outline_rounded,
            onPressed: () {
              Navigator.of(context).pop();
              _confirmDeleteBadCustomer(entry);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteBadCustomer(BlacklistEntry entry) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('حذف العلامة'),
          content: const Text(
            'هل تريد حذف هذه العلامة نهائياً؟ لا يمكن التراجع.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _blacklistSvc.deleteEntry(entry.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('تم حذف العلامة'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 3: Verify it compiles**

Run: `cd D:/glovo_mate && flutter analyze lib/screens/map_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd D:/glovo_mate
git add lib/screens/map_screen.dart
git commit -m "feat(map): bad-customer marker detail sheet + delete"
```

---

## Task 6: Extend the long-press menu with "permanent markers" section

**Files:**
- Modify: `lib/screens/map_screen.dart:398-430` (`_showAlertContextMenu`)

- [ ] **Step 1: Add a section title helper widget at the bottom of the file**

At the end of `lib/screens/map_screen.dart` (after the last existing class, e.g. `_GlassPill` or whatever is last), add a small private widget for the section label:

```dart
class _SheetSectionLabel extends StatelessWidget {
  final String text;
  const _SheetSectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.ink500,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Rewrite `_showAlertContextMenu` to include the permanent-marker tile**

Replace the entire `_showAlertContextMenu` method (lines 398-430) with:

```dart
  /// Long-press menu. Top section: ephemeral alert types. Bottom section:
  /// a single "permanent bad customer" tile that drops a persistent marker.
  void _showAlertContextMenu(LatLng point) {
    AppBottomSheet.show<void>(
      context,
      title: 'إبلاغ عن',
      subtitle: 'اختر نوع البلاغ أو أضف علامة دائمة',
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AlertComposerGrid(
            onSelect: (type) async {
              await _alertSvc.addAlert(
                groupCode: widget.groupCode,
                type: type,
                lat: point.latitude,
                lng: point.longitude,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم الإبلاغ عن ${type.label}'),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          const _SheetSectionLabel(text: 'علامات دائمة'),
          Material(
            color: AppColors.danger.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                _showBadCustomerComposer(point);
              },
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.person_off_rounded,
                        color: AppColors.danger,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text(
                        'زبون سيئ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink900,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_left_rounded,
                      color: AppColors.danger.withValues(alpha: 0.4),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: Verify it compiles** (will fail — `_showBadCustomerComposer` is defined in Task 7)

This is expected; the next task adds the missing method. Skip the analyze step here.

- [ ] **Step 4: Commit (together with Task 7)**

Do not commit yet — the file does not compile. Commit at the end of Task 7.

---

## Task 7: Add the "bad customer" composer sheet

**Files:**
- Modify: `lib/screens/map_screen.dart` — add `_showBadCustomerComposer()` method (place it right after `_showAlertContextMenu`, which now also precedes `_showBadCustomerDetail`)

- [ ] **Step 1: Add the `_showBadCustomerComposer()` method**

Insert this method immediately after the new `_showAlertContextMenu` (before `_showBadCustomerDetail`):

```dart
  /// Composer for dropping a persistent bad-customer marker at [point].
  /// All fields optional — a tap on "حفظ العلامة" with everything empty still
  /// creates a marker (carries only coordinates + audit info).
  void _showBadCustomerComposer(LatLng point) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool saving = false;

    AppBottomSheet.show<void>(
      context,
      title: 'زبون سيئ',
      subtitle: 'العلامة ستبقى على الخريطة حتى يتم حذفها يدوياً',
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      child: StatefulBuilder(
        builder: (ctx, setLocal) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppInput(
                controller: nameCtrl,
                label: 'اسم الزبون (اختياري)',
                hint: 'مثال: محمد',
                leadingIcon: Icons.person_rounded,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: AppSpacing.md),
              AppInput(
                controller: phoneCtrl,
                label: 'رقم الهاتف (اختياري)',
                hint: '06xxxxxxxx',
                leadingIcon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: AppSpacing.md),
              AppInput(
                controller: reasonCtrl,
                label: 'السبب (اختياري)',
                hint: 'لماذا هذا الزبون سيئ؟',
                leadingIcon: Icons.note_rounded,
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'حفظ العلامة',
                leadingIcon: Icons.push_pin_rounded,
                isLoading: saving,
                onPressed: () async {
                  setLocal(() => saving = true);
                  try {
                    await _blacklistSvc.addEntry(
                      lat: point.latitude,
                      lng: point.longitude,
                      name: nameCtrl.text,
                      phone: phoneCtrl.text,
                      reason: reasonCtrl.text,
                    );
                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('تمت إضافة علامة زبون سيئ'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تعذّر حفظ العلامة: $e'),
                          backgroundColor: AppColors.danger,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setLocal(() => saving = false);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
```

- [ ] **Step 2: Verify it compiles**

Run: `cd D:/glovo_mate && flutter analyze lib/screens/map_screen.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit (covers Tasks 6 + 7)**

```bash
cd D:/glovo_mate
git add lib/screens/map_screen.dart
git commit -m "feat(map): long-press menu adds persistent bad-customer marker"
```

---

## Task 8: Bump version and update changelog

**Files:**
- Modify: `pubspec.yaml:4`
- Modify: `CHANGELOG.md` (prepend new entry)

- [ ] **Step 1: Bump `pubspec.yaml` version**

In `pubspec.yaml`, change line 4 from `version: 1.9.3+45` to:

```yaml
version: 1.9.4+46
```

- [ ] **Step 2: Read the current CHANGELOG top entry**

Run: `cd D:/glovo_mate && head -20 CHANGELOG.md`
Note the format used (header style, date format).

- [ ] **Step 3: Prepend a `1.9.4+46` entry to CHANGELOG.md**

Open `CHANGELOG.md` and add a new section at the very top (above the current top entry), matching the existing format. Example content:

```markdown
## 1.9.4+46

- **علامات "زبون سيئ" الدائمة على الخريطة**: اضغط مطولاً على أي نقطة في الخريطة، اختر "زبون سيئ"، وأضف علامة حمراء صغيرة تبقى في مكانها بشكل دائم حتى يتم حذفها يدوياً. يمكن إضافة اسم، رقم هاتف، وسبب (اختياري).
- اضغط على العلامة لعرض التفاصيل أو حذفها.
- العلامات تظهر لجميع المجموعات (عامّة)، مثل قائمة الحظر الحالية.
```

- [ ] **Step 4: Commit**

```bash
cd D:/glovo_mate
git add pubspec.yaml CHANGELOG.md
git commit -m "chore: bump version to 1.9.4+46"
```

---

## Task 9: Full analyze + sanity build

**Files:** none (verification only)

- [ ] **Step 1: Full analyze**

Run: `cd D:/glovo_mate && flutter analyze`
Expected: `No issues found!` (or only pre-existing warnings unrelated to this feature).

- [ ] **Step 2: Build a release APK**

Run: `cd D:/glovo_mate && flutter build apk --release`
Expected: build succeeds, output `build/app/outputs/flutter-apk/app-release.apk`.

If the build fails, read the error, fix the smallest possible change, re-run.

- [ ] **Step 3: Note the APK path and size**

Run: `cd D:/glovo_mate && ls -lh build/app/outputs/flutter-apk/app-release.apk`
Record the path and size for the user.

- [ ] **Step 4: Final commit if any fixes were needed**

If Task 9 Step 2 required code fixes, commit them:

```bash
cd D:/glovo_mate
git add -A
git commit -m "fix: address build/analyze issues from bad-customer markers"
```

---

## Done criteria

- [ ] `flutter analyze` is clean.
- [ ] `flutter build apk --release` succeeds.
- [ ] Long-press on the map shows a "علامات دائمة" section with a "زبون سيئ" tile.
- [ ] Selecting the tile opens a composer; tapping "حفظ العلامة" drops a red marker.
- [ ] The marker shows the icon + "زبون سيئ" label and stays across app restarts.
- [ ] Tapping the marker opens a detail sheet with a delete button.
- [ ] Deleting the marker removes it from the map immediately (stream-driven).
- [ ] Version is `1.9.4+46` and CHANGELOG is updated.
- [ ] APK is built; path reported to user.

---

## Notes for the executor

- This codebase uses CRLF line endings on Windows (Git warns about it). Do not fight it — the `Edit` tool handles this transparently.
- The existing `_AlertComposerGrid` (map_screen.dart:1237) is reused unchanged inside the new menu layout — do not modify it.
- `AppBottomSheet.show` is already imported (map_screen.dart:21).
- The `relativeTime` import already exists (map_screen.dart:22).
- `AppColors.danger`, `AppColors.dangerGradient`, `AppColors.shadowGlowDanger`, `AppColors.success`, `AppColors.surface`, `AppColors.ink*`, `AppRadius.*`, `AppSpacing.*` are all already imported via `app_colors.dart` and `app_spacing.dart` (map_screen.dart:7-9).
- Do NOT touch `blacklist_screen.dart` — its existing call `addEntry(phone: ..., reason: ...)` is still valid against the new optional-parameter signature.
