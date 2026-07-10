<#
.SYNOPSIS
    تثبيت Flutter SDK تلقائياً على Windows.
.DESCRIPTION
    - يحمّل آخر نسخة مستقرة من Flutter
    - يستخرجها في C:\flutter
    - يضيف C:\flutter\bin إلى PATH للمستخدم الحالي
    - لا يحتاج لصلاحيات Administrator (إلا للكتابة في C:\)
.NOTES
    الملف محفوظ بصيغة UTF-8 with BOM لدعم النصوص العربية.
#>

# ─────────── إعداد الترميز UTF-8 للنصوص العربية ───────────
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# فرض TLS 1.2 للتحميلات (مطلوب لبعض إصدارات PowerShell القديمة)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ErrorActionPreference = "Stop"

# ─────────── دوال مساعدة للطباعة ───────────
function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
}
function Write-Ok   { param([string]$Msg) Write-Host "  [نجح] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "  [تنبيه] $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "  [خطأ] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "  [معلومة] $Msg" -ForegroundColor Gray }

# ─────────── العنوان ───────────
Write-Host ""
Write-Host "+----------------------------------------------+" -ForegroundColor Magenta
Write-Host "|      تثبيت Flutter SDK تلقائياً (Windows)      |" -ForegroundColor Magenta
Write-Host "+----------------------------------------------+" -ForegroundColor Magenta

# ─────────────────────────────────────────────────────────────
# الخطوة 1: التحقق من تثبيت Git
# ─────────────────────────────────────────────────────────────
Write-Step "الخطوة 1/6 : التحقق من تثبيت Git"

$gitCmd = Get-Command git.exe -ErrorAction SilentlyContinue
if ($gitCmd) {
    $gitVersion = (git --version) 2>$null
    Write-Ok "Git مثبت بنجاح: $gitVersion"
} else {
    Write-Warn "Git غير مثبت على هذا النظام!"
    Write-Host ""
    Write-Host "  Flutter يحتاج إلى Git ليعمل بشكل صحيح." -ForegroundColor Yellow
    Write-Host "  الرجاء تثبيت Git يدوياً من الموقع الرسمي:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "      https://git-scm.com/download/win" -ForegroundColor White
    Write-Host ""
    Write-Host "  بعد التثبيت، أعد تشغيل هذا السكريبت." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  اضغط Enter للخروج"
    exit 1
}

# ─────────────────────────────────────────────────────────────
# الخطوة 2: التحقق من صلاحية الكتابة في C:\
# ─────────────────────────────────────────────────────────────
Write-Step "الخطوة 2/6 : التحقق من صلاحية الكتابة في C:\"

$installDir  = "C:\flutter"
$flutterExe  = Join-Path $installDir "bin\flutter.bat"

$canWrite = $false
try {
    $testFile = "C:\.flutter_write_test_$(Get-Random)"
    New-Item -Path $testFile -ItemType File -Force -ErrorAction Stop | Out-Null
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    $canWrite = $true
    Write-Ok "الصلاحية متوفرة للكتابة في C:\"
} catch {
    Write-Err "لا يمكن الكتابة في C:\ (يلزم صلاحيات Administrator)"
    Write-Host ""
    Write-Host "  الحلول المقترحة:" -ForegroundColor Yellow
    Write-Host "    1. أغلق النافذة، ثم شغّل PowerShell كمسؤول" -ForegroundColor White
    Write-Host "       (Run as Administrator) وأعد تشغيل هذا السكريبت." -ForegroundColor White
    Write-Host "    2. أو ثبّت Flutter في مجلد المستخدم:" -ForegroundColor White
    Write-Host "       C:\Users\$env:USERNAME\flutter" -ForegroundColor White
    Write-Host ""
    Read-Host "  اضغط Enter للخروج"
    exit 1
}

# ─────────────────────────────────────────────────────────────
# الخطوة 3: التحقق من تثبيت Flutter مسبقاً + جلب آخر نسخة
# ─────────────────────────────────────────────────────────────
Write-Step "الخطوة 3/6 : جلب آخر نسخة مستقرة من Flutter"

$releasesUrl = "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"
try {
    $manifest = Invoke-RestMethod -Uri $releasesUrl -UseBasicParsing
} catch {
    Write-Err "فشل الاتصال بخادم Flutter. تحقق من اتصال الإنترنت."
    Write-Info "التفاصيل: $($_.Exception.Message)"
    Read-Host "`n  اضغط Enter للخروج"
    exit 1
}

$stableHash = $manifest.current_release.stable
$stable = $manifest.releases | Where-Object { $_.hash -eq $stableHash } | Select-Object -First 1

if (-not $stable) {
    Write-Err "تعذر العثور على معلومات النسخة المستقرة."
    Read-Host "`n  اضغط Enter للخروج"
    exit 1
}

$version      = $stable.version
$downloadUrl  = "$($manifest.base_url)/$($stable.archive)"

Write-Ok "آخر نسخة مستقرة: Flutter v$version"

# إذا كان Flutter موجوداً مسبقاً
if (Test-Path $flutterExe) {
    Write-Warn "Flutter موجود مسبقاً في: $installDir"
    Write-Host ""
    $choice = Read-Host "  إعادة التثبيت ستحذف المجلد الحالي. هل تريد المتابعة؟ (y/n)"
    if ($choice -notin @('y','Y')) {
        Write-Info "تم الإلغاء. الاحتفاظ بالتثبيت الحالي."
        # اذهب مباشرة لإضافة PATH
        $skipInstall = $true
    } else {
        Write-Info "جاري حذف التثبيت الحالي..."
        try {
            Remove-Item -Recurse -Force $installDir -ErrorAction Stop
        } catch {
            Write-Err "تعذر حذف المجلد. تأكد من إغلاق أي محرر يستخدمه."
            Read-Host "`n  اضغط Enter للخروج"
            exit 1
        }
        $skipInstall = $false
    }
} else {
    $skipInstall = $false
}

if (-not $skipInstall) {
    # ─────────────────────────────────────────────────────────
    # الخطوة 4: تحميل Flutter SDK
    # ─────────────────────────────────────────────────────────
    Write-Step "الخطوة 4/6 : تحميل Flutter SDK"

    $tempZip = Join-Path $env:TEMP "flutter_windows_$version.zip"
    Write-Info "المسار المؤقت: $tempZip"
    Write-Info "الحجم تقريباً 1GB، التحميل قد يستغرق عدة دقائق..."
    Write-Host ""

    $ProgressPreference = 'Continue'
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing
    } catch {
        Write-Err "فشل التحميل: $($_.Exception.Message)"
        Read-Host "`n  اضغط Enter للخروج"
        exit 1
    }

    if (-not (Test-Path $tempZip)) {
        Write-Err "الملف لم يُحمّل بشكل صحيح."
        Read-Host "`n  اضغط Enter للخروج"
        exit 1
    }

    $sizeMB = [math]::Round((Get-Item $tempZip).Length / 1MB, 1)
    Write-Ok "اكتمل التحميل ($sizeMB MB)"

    # ─────────────────────────────────────────────────────────
    # الخطوة 5: الاستخراج في C:\
    # ─────────────────────────────────────────────────────────
    Write-Step "الخطوة 5/6 : استخراج الملفات إلى C:\flutter"
    Write-Info "هذه العملية قد تستغرق عدة دقائق، يرجى الانتظار..."

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, "C:\")
    } catch {
        Write-Err "فشل الاستخراج: $($_.Exception.Message)"
        Read-Host "`n  اضغط Enter للخروج"
        exit 1
    }

    if (Test-Path $flutterExe) {
        Write-Ok "تم الاستخراج بنجاح في $installDir"
    } else {
        Write-Err "اكتمل الاستخراج لكن flutter.bat غير موجود."
        Write-Info "تحقق من محتوى المجلد C:\"
        Read-Host "`n  اضغط Enter للخروج"
        exit 1
    }

    # حذف الملف المؤقت
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Write-Info "تم حذف الملف المضغوط المؤقت"
}

# ─────────────────────────────────────────────────────────────
# الخطوة 6: إضافة C:\flutter\bin إلى PATH للمستخدم الحالي
# ─────────────────────────────────────────────────────────────
Write-Step "الخطوة 6/6 : إضافة C:\flutter\bin إلى PATH (المستخدم)"

$flutterBin = "$installDir\bin"
$userPath   = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts  = if ($userPath) { $userPath -split ';' } else { @() }

if ($pathParts -contains $flutterBin) {
    Write-Ok "المسار موجود مسبقاً في PATH للمستخدم"
} else {
    $newPath = if ([string]::IsNullOrEmpty($userPath)) {
        $flutterBin
    } else {
        "$userPath;$flutterBin"
    }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Ok "تمت إضافة المسار إلى PATH للمستخدم الحالي بنجاح"
}

# تحديث PATH في الجلسة الحالية أيضاً (حتى يعمل flutter فوراً)
if (($env:Path -split ';') -notcontains $flutterBin) {
    $env:Path = "$env:Path;$flutterBin"
}

# ─────────────────────────────────────────────────────────────
# النهاية: التحقق وملخص
# ─────────────────────────────────────────────────────────────
Write-Step "اكتمل التثبيت بنجاح!"

# محاولة تشغيل flutter للتحقق
try {
    $fv = & flutter --version 2>&1 | Select-Object -First 1
    Write-Ok "التحقق: $fv"
} catch {
    Write-Info "سيكون أمر flutter متاحاً بعد فتح نافذة جديدة."
}

Write-Host ""
Write-Host "  ملاحظات مهمة:" -ForegroundColor Yellow
Write-Host "  1. أغلق هذه النافذة وافتح PowerShell أو CMD جديدة" -ForegroundColor White
Write-Host "     ليصبح أمر flutter متاحاً في كل مكان." -ForegroundColor White
Write-Host "  2. شغّل الأمر التالي للتحقق من التثبيت:" -ForegroundColor White
Write-Host ""
Write-Host "        flutter doctor" -ForegroundColor Cyan
Write-Host ""
Write-Host "  3. ستظهر قائمة بالمتطلبات (Android Studio، إلخ)." -ForegroundColor White
Write-Host "  4. لربط مشروعك الحالي بـ Flutter:" -ForegroundColor White
Write-Host ""
Write-Host "        cd D:\glovo_mate" -ForegroundColor Cyan
Write-Host "        flutter pub get" -ForegroundColor Cyan
Write-Host ""
Write-Ok "Flutter جاهز في: $installDir"

Write-Host ""
Read-Host "  اضغط Enter للإنهاء"
