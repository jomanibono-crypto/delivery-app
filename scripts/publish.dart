import 'dart:convert';
import 'dart:io';

// ─────────────────────────────────────────────────────────────────
// glovo_mate Publish Script
// ─────────────────────────────────────────────────────────────────
// Usage:
//   dart run scripts/publish.dart [--changelog "text"] [--major|--minor|--patch]
//   dart run scripts/publish.dart --setup   # first-time GitHub token setup
//   dart run scripts/publish.dart --status  # check current status
// ─────────────────────────────────────────────────────────────────

const _configPath = 'scripts/.publish_config.json';
const _pubspecPath = 'pubspec.yaml';
const _apkPath = 'build/app/outputs/flutter-apk/app-release.apk';
const _firebaseApiKey = 'AIzaSyAwTGrrkv-dSdryC8r6aygmYfNUzmZivV4';
const _firebaseDbUrl = 'https://track-the-delivery-drivers-default-rtdb.firebaseio.com';
const _githubApi = 'https://api.github.com';

// ──────────────────── Data classes ────────────────────

class PublishConfig {
  final String githubToken;
  final String repoOwner;
  final String repoName;

  PublishConfig({
    required this.githubToken,
    required this.repoOwner,
    required this.repoName,
  });

  Map<String, dynamic> toJson() => {
        'github_token': githubToken,
        'repo_owner': repoOwner,
        'repo_name': repoName,
      };

  factory PublishConfig.fromJson(Map<String, dynamic> json) => PublishConfig(
        githubToken: json['github_token'] as String? ?? '',
        repoOwner: json['repo_owner'] as String? ?? '',
        repoName: json['repo_name'] as String? ?? '',
      );
}

class VersionInfo {
  final String version; // "1.0.8"
  final int buildNumber; // 9

  VersionInfo({required this.version, required this.buildNumber});

  List<int> get parts => version.split('.').map(int.parse).toList();

  VersionInfo bump({bool major = false, bool minor = false, bool patch = true}) {
    final p = parts;
    if (major) {
      p[0]++; p[1] = 0; p[2] = 0;
    } else if (minor) {
      p[1]++; p[2] = 0;
    } else {
      p[2]++;
    }
    return VersionInfo(
      version: p.join('.'),
      buildNumber: buildNumber + 1,
    );
  }

  factory VersionInfo.fromPubspec(String content) {
    final verMatch = RegExp(r'version:\s*(\d+\.\d+\.\d+)\+(\d+)').firstMatch(content);
    if (verMatch == null) throw Exception('Could not parse version from pubspec.yaml');
    return VersionInfo(
      version: verMatch.group(1)!,
      buildNumber: int.parse(verMatch.group(2)!),
    );
  }
}

// ──────────────────── Config ────────────────────

PublishConfig _loadConfig() {
  final file = File(_configPath);
  if (!file.existsSync()) {
    print('''
┌──────────────────────────────────────────────┐
│  ⚠️  No publish config found.                  │
│  Run: dart run scripts/publish.dart --setup   │
└──────────────────────────────────────────────┘
''');
    exit(1);
  }
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return PublishConfig.fromJson(json);
}

void _saveConfig(PublishConfig config) {
  final file = File(_configPath);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(config.toJson()));
  print('✅ Config saved to $_configPath');
}

void _runSetup() {
  print('''
┌──────────────────────────────────────────────┐
│  🚀 glovo_mate Publish Setup                 │
└──────────────────────────────────────────────┘
''');

  stdout.write('GitHub Personal Access Token (classic, with repo scope): ');
  final token = stdin.readLineSync()?.trim() ?? '';
  if (token.isEmpty) { print('❌ Token required.'); exit(1); }

  stdout.write('Repository owner (e.g. jomanibono-crypto): ');
  final owner = stdin.readLineSync()?.trim() ?? '';
  if (owner.isEmpty) { print('❌ Owner required.'); exit(1); }

  stdout.write('Repository name (e.g. delivery-app): ');
  final repo = stdin.readLineSync()?.trim() ?? '';
  if (repo.isEmpty) { print('❌ Repo name required.'); exit(1); }

  // Verify token by calling GitHub API
  print('\n🔍 Verifying token...');
  final result = _githubRequest('GET', '/repos/$owner/$repo', token: token);
  if (result['error'] != null) {
    print('❌ Token verification failed: ${result['error']}');
    exit(1);
  }

  _saveConfig(PublishConfig(githubToken: token, repoOwner: owner, repoName: repo));

  if (!File(_configPath).existsSync()) {
    // Add to .gitignore if not already
    final gitignore = File('.gitignore');
    final content = gitignore.readAsStringSync();
    if (!content.contains('.publish_config.json')) {
      gitignore.writeAsStringSync('\n# Publish config (contains GitHub token)\n.publish_config.json\n', mode: FileMode.append);
      print('✅ Added .publish_config.json to .gitignore');
    }
  }

  print('''
┌──────────────────────────────────────────────┐
│  ✅ Setup complete!                           │
│                                                │
│  Now run:                                     │
│  dart run scripts/publish.dart "وصف التحديث"  │
└──────────────────────────────────────────────┘
''');
}

void _runStatus() {
  // Check config
  final configFile = File(_configPath);
  final configExists = configFile.existsSync();

  if (configExists) {
    final config = _loadConfig();
    print('🔑 GitHub Token: ${config.githubToken.substring(0, 8)}... (${config.githubToken.length} chars)');
    print('📦 Repo: ${config.repoOwner}/${config.repoName}');

    // Check GitHub API
    final result = _githubRequest('GET', '/repos/${config.repoOwner}/${config.repoName}', token: config.githubToken);
    if (result['error'] != null) {
      print('❌ GitHub API: ${result['error']}');
    } else {
      print('✅ GitHub API: connected');
    }
  } else {
    print('❌ No config found — run --setup first');
  }

  // Check pubspec version
  try {
    final pubspec = File(_pubspecPath).readAsStringSync();
    final v = VersionInfo.fromPubspec(pubspec);
    print('📱 App version: ${v.version}+${v.buildNumber}');
  } catch (e) {
    print('❌ Could not read version: $e');
  }

  // Check Firebase
  try {
    final client = HttpClient();
    client.getUrl(Uri.parse('$_firebaseDbUrl/app_version.json'))
        .then((req) => req.close())
        .then((res) => res.transform(utf8.decoder).join())
        .then((body) {
      if (body.contains('"latest_version"')) {
        final data = jsonDecode(body);
        print('✅ Firebase: v${data['latest_version'] ?? 'unknown'}');
        print('🔗 URL: ${data['download_url'] ?? 'none'}');
        print('📝 Changelog: ${data['changelog'] ?? 'none'}');
      } else {
        print('❌ Firebase: no app_version node or permission denied');
      }
    });
  } catch (e) {
    print('❌ Firebase check failed: $e');
  }
}

// ──────────────────── GitHub API ────────────────────

Map<String, dynamic> _githubRequest(
  String method,
  String path, {
  String? token,
  Map<String, dynamic>? body,
  List<int>? fileBytes,
  String? fileName,
}) {
  try {
    final client = HttpClient();
    final uri = Uri.parse('$_githubApi$path');
    HttpClientRequest req;

    if (fileBytes != null && fileName != null) {
      // Upload asset as POST with binary body
      req = client.postUrl(uri);
    } else {
      switch (method) {
        case 'GET': req = client.getUrl(uri); break;
        case 'POST': req = client.postUrl(uri); break;
        case 'PATCH': req = client.patchUrl(uri); break;
        case 'DELETE': req = client.deleteUrl(uri); break;
        case 'PUT': req = client.putUrl(uri); break;
        default: throw Exception('Unknown method: $method');
      }
    }

    req.headers.set('User-Agent', 'glovo_mate-publish-script');
    req.headers.set('Accept', 'application/vnd.github.v3+json');
    if (token != null && token.isNotEmpty) {
      req.headers.set('Authorization', 'Bearer $token');
    }

    if (body != null) {
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode(body));
    }

    if (fileBytes != null && fileName != null) {
      req.headers.set('Content-Type', 'application/vnd.android.package-archive');
      req.headers.set('Content-Disposition', 'attachment; filename="$fileName"');
      req.add(fileBytes);
    }

    final res = req.close();
    final responseBody = res.transform(utf8.decoder).join();

    if (responseBody.isNotEmpty) {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      if (decoded.containsKey('message') && !decoded.containsKey('id')) {
        return {'error': decoded['message']};
      }
      return decoded;
    }
    return {};
  } catch (e) {
    return {'error': e.toString()};
  }
}

// ──────────────────── Firebase REST ────────────────────

Future<String?> _getFirebaseToken() async {
  try {
    final client = HttpClient();
    final uri = Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_firebaseApiKey');
    final req = await client.postUrl(uri);
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode({'returnSecureToken': true}));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    return data['idToken'] as String?;
  } catch (e) {
    print('❌ Firebase auth error: $e');
    return null;
  }
}

Future<bool> _updateFirebaseAppVersion({
  required String version,
  required String downloadUrl,
  required String changelog,
  required int fileSize,
}) async {
  print('📤 Updating Firebase app_version...');
  final token = await _getFirebaseToken();
  if (token == null) return false;

  try {
    final client = HttpClient();
    final uri = Uri.parse('$_firebaseDbUrl/app_version.json?auth=$token');
    final req = await client.putUrl(uri);
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode({
      'latest_version': version,
      'download_url': downloadUrl,
      'changelog': changelog,
      'file_size': fileSize,
      'published_at': DateTime.now().toIso8601String(),
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (body.contains('"latest_version"')) {
      print('✅ Firebase updated to v$version');
      return true;
    } else {
      print('❌ Firebase write failed: $body');
      return false;
    }
  } catch (e) {
    print('❌ Firebase write error: $e');
    return false;
  }
}

// ──────────────────── GitHub Release ────────────────────

Future<String?> _createGitHubRelease({
  required String token,
  required String owner,
  required String repo,
  required String tag,
  required String name,
  required String body,
}) async {
  print('📦 Creating GitHub release $tag...');

  // Check if release already exists
  final checkResult = _githubRequest('GET', '/repos/$owner/$repo/releases/tags/$tag', token: token);
  if (checkResult['error'] == null && checkResult['upload_url'] != null) {
    print('✅ Release $tag already exists');
    return checkResult['html_url'] as String?;
  }

  final result = _githubRequest('POST', '/repos/$owner/$repo/releases', token: token, body: {
    'tag_name': tag,
    'name': name,
    'body': body,
    'draft': false,
    'prerelease': false,
  });

  if (result['error'] != null) {
    print('❌ Failed to create release: ${result['error']}');
    return null;
  }

  final url = result['html_url'] as String?;
  print('✅ Release created: $url');
  return url;
}

Future<String?> _uploadApkToRelease({
  required String token,
  required String owner,
  required String repo,
  required String tag,
  required String apkPath,
}) async {
  print('📤 Uploading APK to GitHub release...');

  // Get release by tag
  final releaseResult = _githubRequest('GET', '/repos/$owner/$repo/releases/tags/$tag', token: token);
  if (releaseResult['error'] != null) {
    print('❌ Could not find release $tag: ${releaseResult['error']}');
    return null;
  }

  final releaseId = releaseResult['id'];
  final uploadUrlTemplate = releaseResult['upload_url'] as String;

  // Check if asset already exists, delete it
  final assetsResult = _githubRequest('GET', '/repos/$owner/$repo/releases/$releaseId/assets', token: token);
  if (assetsResult is List) {
    for (final asset in assetsResult) {
      if (asset['name'] == 'app-release.apk') {
        print('🗑️ Removing existing asset: app-release.apk');
        _githubRequest('DELETE', '/repos/$owner/$repo/releases/assets/${asset['id']}', token: token);
      }
    }
  }

  // Upload the APK
  final file = File(apkPath);
  if (!file.existsSync()) {
    print('❌ APK not found at $apkPath');
    return null;
  }

  final fileBytes = file.readAsBytesSync();
  final fileSize = fileBytes.length;

  try {
    final client = HttpClient();
    final uploadUri = Uri.parse('https://uploads.github.com/repos/$owner/$repo/releases/$releaseId/assets?name=app-release.apk');
    final req = await client.postUrl(uploadUri);
    req.headers.set('User-Agent', 'glovo_mate-publish-script');
    req.headers.set('Accept', 'application/vnd.github.v3+json');
    req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Content-Type', 'application/vnd.android.package-archive');
    req.contentLength = fileSize;
    req.add(fileBytes);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;

    if (data.containsKey('state') && data['state'] == 'uploaded') {
      final downloadUrl = 'https://github.com/$owner/$repo/releases/download/$tag/app-release.apk';
      print('✅ APK uploaded ($fileSize bytes)');
      print('🔗 Download URL: $downloadUrl');
      return downloadUrl;
    } else {
      print('❌ Upload failed: $body');
      return null;
    }
  } catch (e) {
    print('❌ Upload error: $e');
    return null;
  }
}

// ──────────────────── Main ────────────────────

void main(List<String> args) async {
  print('''
┌──────────────────────────────────────────────┐
│  🚀 glovo_mate Publisher v1.0               │
└──────────────────────────────────────────────┘
''');

  if (args.contains('--setup')) {
    _runSetup();
    return;
  }

  if (args.contains('--status')) {
    _runStatus();
    return;
  }

  // ── Parse args ──
  String changelog = '';
  bool major = false, minor = false, patch = true;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--changelog' && i + 1 < args.length) {
      changelog = args[++i];
    } else if (args[i] == '--major') {
      major = true; minor = false; patch = false;
    } else if (args[i] == '--minor') {
      minor = true; major = false; patch = false;
    } else if (args[i] == '--patch') {
      patch = true; major = false; minor = false;
    } else if (!args[i].startsWith('--')) {
      changelog = args[i];
    }
  }

  // ── Load config ──
  final config = _loadConfig();

  // ── Read and bump version ──
  print('📖 Reading pubspec.yaml...');
  final pubspecContent = File(_pubspecPath).readAsStringSync();
  final currentVersion = VersionInfo.fromPubspec(pubspecContent);
  final newVersion = currentVersion.bump(major: major, minor: minor, patch: patch);
  final tag = 'v${newVersion.version}';

  print('📱 Current: v${currentVersion.version}+${currentVersion.buildNumber}');
  print('📱 New:     v${newVersion.version}+${newVersion.buildNumber}');

  // Validate: ensure version comparison (new > old)
  if (!_isNewer(newVersion.version, currentVersion.version)) {
    print('❌ New version must be greater than current version');
    exit(1);
  }

  // ── Prompt for changelog if not provided ──
  if (changelog.isEmpty) {
    stdout.write('📝 Enter changelog (or press Enter for default): ');
    changelog = stdin.readLineSync()?.trim() ?? '';
    if (changelog.isEmpty) {
      changelog = 'إصلاح الأخطاء وتحسين الأداء';
    }
  }

  print('');

  // ── Update pubspec.yaml ──
  print('📝 Updating pubspec.yaml...');
  final newPubspec = pubspecContent.replaceFirst(
    RegExp(r'version:\s*\d+\.\d+\.\d+\+\d+'),
    'version: ${newVersion.version}+${newVersion.buildNumber}',
  );
  File(_pubspecPath).writeAsStringSync(newPubspec);
  print('✅ Version updated to v${newVersion.version}+${newVersion.buildNumber}');

  // ── Build APK ──
  print('\n🔨 Building APK (this may take a while)...');
  final buildResult = await Process.run(
    'flutter', ['build', 'apk', '--release'],
    workingDirectory: Directory.current.path,
    runInShell: true,
  );
  if (buildResult.exitCode != 0) {
    print('❌ Build failed:\n${buildResult.stderr}');
    // Restore pubspec.yaml
    File(_pubspecPath).writeAsStringSync(pubspecContent);
    print('↩️ Version restored to v${currentVersion.version}+${currentVersion.buildNumber}');
    exit(1);
  }
  print('✅ APK built successfully');

  // ── Create GitHub Release ──
  print('');
  final releaseUrl = await _createGitHubRelease(
    token: config.githubToken,
    owner: config.repoOwner,
    repo: config.repoName,
    tag: tag,
    name: 'v${newVersion.version} - $changelog',
    body: changelog,
  );
  if (releaseUrl == null) {
    // Restore pubspec.yaml
    File(_pubspecPath).writeAsStringSync(pubspecContent);
    print('↩️ Version restored to v${currentVersion.version}+${currentVersion.buildNumber}');
    exit(1);
  }

  // ── Upload APK ──
  print('');
  final downloadUrl = await _uploadApkToRelease(
    token: config.githubToken,
    owner: config.repoOwner,
    repo: config.repoName,
    tag: tag,
    apkPath: _apkPath,
  );
  if (downloadUrl == null) {
    File(_pubspecPath).writeAsStringSync(pubspecContent);
    print('↩️ Version restored');
    exit(1);
  }

  // ── Get file size ──
  final apkFile = File(_apkPath);
  final fileSize = apkFile.lengthSync();

  // ── Update Firebase ──
  print('');
  final firebaseOk = await _updateFirebaseAppVersion(
    version: newVersion.version,
    downloadUrl: downloadUrl,
    changelog: changelog,
    fileSize: fileSize,
  );

  if (!firebaseOk) {
    print('⚠️  APK uploaded but Firebase update failed. Update manually.');
  }

  // ── Commit version bump ──
  print('\n📦 Committing version bump...');
  try {
    await Process.run('git', ['add', 'pubspec.yaml'], runInShell: true);
    await Process.run('git', ['commit', '-m', 'Bump version to v${newVersion.version}+${newVersion.buildNumber}'], runInShell: true);
    await Process.run('git', ['tag', tag], runInShell: true);
    stdout.write('🚀 Push to GitHub? (y/N): ');
    final push = stdin.readLineSync()?.trim().toLowerCase();
    if (push == 'y' || push == 'yes') {
      await Process.run('git', ['push', 'origin', 'master', '--tags'], runInShell: true);
      print('✅ Pushed to GitHub');
    } else {
      print('⏸️  Not pushed. Run: git push origin master --tags');
    }
  } catch (e) {
    print('⚠️  Git commit/push skipped: $e');
  }

  // ── Done ──
  print('''
┌──────────────────────────────────────────────┐
│  ✅ PUBLISH COMPLETE!                         │
│                                                │
│  Version:  v${newVersion.version}+${newVersion.buildNumber}
│  Tag:      $tag
│  Download: $downloadUrl
│  Firebase: ${firebaseOk ? '✅ Updated' : '❌ Failed'}
└──────────────────────────────────────────────┘
''');
}

bool _isNewer(String latest, String current) {
  final latestParts = latest.split('.').map(int.parse).toList();
  final currentParts = current.split('.').map(int.parse).toList();
  while (latestParts.length < currentParts.length) latestParts.add(0);
  while (currentParts.length < latestParts.length) currentParts.add(0);
  for (var i = 0; i < latestParts.length; i++) {
    if (latestParts[i] > currentParts[i]) return true;
    if (latestParts[i] < currentParts[i]) return false;
  }
  return false;
}
