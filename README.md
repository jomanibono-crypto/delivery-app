# GlovoMate

تطبيق مشاركة الموقع الجغرافي اللحظي للمجموعات الصغيرة مع إشعارات القرب.

## الميزات

- مشاركة الموقع اللحظي عبر Firebase Realtime Database
- تسجيل دخول مجهول (بدون اشتراك)
- خريطة OpenStreetMap عبر `flutter_map`
- إشعارات القرب عبر `flutter_local_notifications`
- مسار الرحلة على الخريطة مع Polyline
- عرض سرعة العضو ووقت التوقف عند النقر على العلامة

## بدء التطوير

1. ثبت Flutter SDK (انظر `setup_flutter.ps1` لتثبيت آلي على Windows)
2. `flutter pub get`
3. `flutter build apk --release` لبناء APK

## نشر الإصدارات

### عبر GitHub Actions (مستحسن)

1. ادفع tag للإصدار الجديد:
   ```
   git tag v1.0.9
   git push origin v1.0.9
   ```
2. GitHub Actions سيبني APK، وينشئ GitHub Release، ويحدث Firebase تلقائياً

### عبر CLI محلياً

```
dart run scripts/publish.dart "رسالة التحديث"
```

- يقرأ GitHub Token من `scripts/.publish_config.json` (ملف محلي، غير مضمن في git)
- يبني APK، ينشئ GitHub Release، ويحدث Firebase

### الإعداد لمرة واحدة

1. أنشئ GitHub Personal Access Token (`Settings > Developer settings > Personal access tokens > Fine-grained tokens`)
2. الصلاحيات المطلوبة: `Contents: write` (لإنشاء Releases)
3. شغل `dart run scripts/publish.dart --setup` لإدخال التوكن

## الأمان

- لا توجد أسرار حقيقية في الكود — Firebase Web API و Mapbox tokens هي مفاتيح عامة مخصصة للاستخدام من جانب العميل
- GitHub PAT يُخزن فقط محلياً في `.publish_config.json` (مدرج في `.gitignore`)
- في CI، يُقرأ PAT من `GITHUB_TOKEN` env var (مؤمن بواسطة GitHub Actions)
