# Persistent "Bad Customer" Map Markers

**Date:** 2026-07-19
**Status:** Approved (brainstormed)
**Target version:** `1.9.4+46` (from `1.9.3+45`)

## Goal

Allow delivery drivers to drop a **small, persistent** marker on the map for a bad
customer. The marker displays an icon plus the text label **"زبون سيئ"** and
**never disappears on its own** — it stays at the pinned location until a user
explicitly deletes it.

## Background

- The app uses `flutter_map` ^8.1.0. Markers are ordinary Flutter widgets
  rendered via `MarkerLayer`, driven by `ValueNotifier`s.
- An `AlertType.badCustomer` ("🚫 عميل سيء") already exists, but it is an
  **ephemeral 12-hour alert** that is auto-cleaned and not tied to the phone
  blacklist. It is a separate concept and stays untouched.
- `BlacklistService` stores phone-based entries under a **global** Firebase node
  `blacklist/{pushKey}` (no TTL, no per-group scoping). Entries currently have
  `phone`, `normalized`, `reason`, `addedBy`, `addedByName`, `timestamp` — no
  location.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| How is a marker added? | **Long-press** on the map (reuses existing `_onLongPress`). |
| What is shown on the marker? | Red circular icon + label "زبون سيئ" + optional phone/reason details |
| Relationship with existing alert | **New independent layer**; old `badCustomer` alert stays as-is |
| Storage | **Merge with existing blacklist** (extend `BlacklistEntry`) |
| Visibility | **Global** — visible to all groups (matches current blacklist) |
| Required fields on add | **All optional** — phone, reason, name (lat/lng come from tap point) |

## Design

### 1. Data model — extend `BlacklistEntry`

Add three nullable fields. Old entries deserialize unchanged.

| Field | Type | Default | Notes |
|---|---|---|---|
| `lat` | `double?` | `null` | `null` ⇒ phone-only entry (no marker) |
| `lng` | `double?` | `null` | |
| `name` | `String?` | `null` | Optional customer name shown in detail sheet |

`BlacklistEntry.fromMap` reads them defensively:
`lat: (map['lat'] as num?)?.toDouble()`.

A marker exists iff `lat != null && lng != null`.

### 2. Storage (Firebase)

Same global node `blacklist/{pushKey}`. Entries now split into two implicit
kinds:

- **Phone-only** (legacy + new phone adds): `lat == null`
- **Markers** (new): `lat != null`, optional `phone`/`reason`/`name`

No schema migration; existing rows keep working because `lat`/`lng`/`name`
default to `null`.

### 3. `BlacklistService` API

- `addEntry({String? phone, String? reason, double? lat, double? lng, String? name})`
  - All parameters optional. At least one of `{phone, lat}` should be present
    (UI enforces this — marker flow always has `lat`).
  - Writes `phone`/`normalized` only when `phone` is non-empty (so a pure
    marker doesn't pollute the normalized lookup index).
  - Writes `lat`/`lng`/`name` only when provided.
- `deleteEntry(String entryId)` — unchanged; works for both kinds.
- `watchAll()` — unchanged.
- **New:** `Stream<List<BlacklistEntry>> watchMarkers()` —
  `watchAll().map((l) => l.where((e) => e.lat != null && e.lng != null).toList())`.

### 4. Map screen — new `MarkerLayer`

In `map_screen.dart` `build()`, add a third `MarkerLayer` (between the alerts
layer and the members layer) wrapped in a `ValueListenableBuilder` over a new
`ValueNotifier<List<BlacklistEntry>> _badCustomerNotifier`.

Subscription wiring (in `initState` alongside the existing
`_fb.watchGroupMembers` / `_alertSvc.watchAlerts` subscriptions):

```dart
_blacklistSub = _blacklistSvc.watchMarkers().listen((entries) {
  _badCustomerNotifier.value = entries;
});
```

Cancelled in `dispose()`.

Because the notifier only ever grows/shrinks by user action (delete), markers
persist across rebuilds and app restarts. There is no TTL, no cleanup timer.

### 5. Marker visual

Matches existing `_buildAlertMarkers` style for consistency:

```
Marker(width: 110, height: 70, point: LatLng(entry.lat, entry.lng), child:
  GestureDetector(
    onTap: () => _showBadCustomerDetail(entry),
    child: Column(children: [
      Container(  // 40px circle, dangerGradient, white border, shadow
        width: 40, height: 40,
        decoration: BoxDecoration(
          gradient: AppColors.dangerGradient,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: [AppColors.shadowGlowDanger],
        ),
        child: Icon(Icons.person_off_rounded, color: Colors.white, size: 20),
      ),
      Container(  // black label pill
        margin: EdgeInsets.only(top: 3),
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black87, borderRadius: BorderRadius.circular(6)),
        child: Text('زبون سيئ',
          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: w600)),
      ),
    ]),
  ),
)
```

### 6. Add flow — long-press menu

`_onLongPress(TapPosition, LatLng)` currently calls `_showAlertContextMenu(point)`.

Modify `_showAlertContextMenu` (an `AppBottomSheet.show`) to add a small
**"permanent markers"** section below the existing alert grid:

- Title still "إبلاغ عن", but the sheet now contains:
  - **Section "بلاغات"** → the existing 6-tile alert grid (unchanged behavior)
  - **Section "علامات دائمة"** → one tile: "🚫 زبون سيئ" (red, dangerGradient)
- Selecting "زبون سيئ" opens a second `AppBottomSheet` with optional fields:
  - اسم الزبون (name) — optional
  - رقم الهاتف (phone) — optional
  - السبب (reason) — optional
  - "حفظ العلامة" button → `_blacklistSvc.addEntry(lat: point.latitude, lng:
    point.longitude, phone: ..., reason: ..., name: ...)` → SnackBar
    "تمت إضافة علامة زبون سيئ" → pop.

### 7. Detail sheet + delete

`_showBadCustomerDetail(BlacklistEntry entry)` opens an `AppBottomSheet`:

- Header: red icon container + label "زبون سيئ"
- Info rows (each shown only if present):
  - الاسم: `entry.name`
  - الهاتف: `entry.phone`
  - السبب: `entry.reason`
  - أضيفت بواسطة: `entry.addedByName`
  - التاريخ: relative-time-formatted `entry.timestamp`
- Footer button **"حذف العلامة"** (red) → confirm dialog →
  `_blacklistSvc.deleteEntry(entry.id)` → SnackBar → pop.

### 8. Persistence guarantee

The persistence contract ("تبقى ديما تماك، ما تتمسحش") is satisfied by:

1. The Firebase node `blacklist/` has **no TTL** and **no cleanup timer**
   (unlike `cleanupExpiredAlerts` which runs every 12h for alerts).
2. The marker builder filters only on `lat != null` and adds nothing that
   expires.
3. The only removal path is `deleteEntry` triggered from the detail sheet.

## Files touched

| File | Change |
|---|---|
| `lib/services/blacklist_service.dart` | Extend `BlacklistEntry` (`lat`, `lng`, `name`); extend `addEntry` signature; add `watchMarkers()`. |
| `lib/screens/map_screen.dart` | Add `_badCustomerNotifier`, subscription; new `MarkerLayer`; `_showBadCustomerDetail`; extend `_showAlertContextMenu` with the "permanent markers" section + composer sheet; bump version display if shown. |
| `lib/screens/blacklist_screen.dart` | (Optional, light) marker entries (those with `lat`) render with a small pin glyph so they are visually distinguishable in the list. Non-blocking. |
| `pubspec.yaml` | `version: 1.9.4+46` |
| `CHANGELOG.md` | Entry for `1.9.4+46`. |

## Out of scope

- Editing an existing marker (only add + delete).
- Per-group scoping (stays global, matching the current blacklist).
- Bulk import/export of markers.
- Any change to the existing `AlertType.badCustomer` alert.
- iOS build (this release targets Android APK only, per user's "رفع للتليفون").

## Risks / notes

- Global node means a marker dropped by group A is visible to group B. This is
  consistent with the existing phone blacklist behavior and was explicitly
  approved.
- Old phone-only entries have `lat == null` and are filtered out of the marker
  layer — they keep showing in the blacklist screen as before.
- A marker with empty phone will not appear in `checkPhone` lookups; that's
  correct since it carries no phone.
