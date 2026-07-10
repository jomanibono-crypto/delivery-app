import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_service.dart';
import '../services/local_storage_service.dart';
import 'home_screen.dart';

/// Create or Join a group screen.
/// - "Create Group" generates a random 6-digit code
/// - "Join Group" lets user enter a code + their name
/// All data is ephemeral — no persistent storage.
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final LocalStorageService _localStorage = LocalStorageService();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  /// Create a new group with a random 6-digit code.
  Future<void> _createGroup() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'أدخل اسمك أولاً');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final code = await _firebaseService.createGroup();
      _codeController.text = code;

      // Persist session so the user skips the form next launch.
      final userName = _nameController.text.trim();
      await _localStorage.saveSession(userName: userName, groupCode: code);

      // Copy code to clipboard for easy sharing
      await Clipboard.setData(ClipboardData(text: code));

      if (mounted) {
        // Navigate straight to Home (don't just show a snackbar).
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(groupCode: code, userName: userName),
          ),
        );
      }
    } catch (e, st) {
      // Print the FULL exception + stack trace to console for debugging.
      debugPrint('[CreateGroup] ERROR: ${e.toString()}');
      debugPrint('[CreateGroup] STACK TRACE:\n$st');
      final msg = 'فشل في إنشاء المجموعة: ${e.toString()}';
      setState(() => _errorMessage = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Join an existing group using a code and user name.
  Future<void> _joinGroup() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();

    if (code.length != 6) {
      setState(() => _errorMessage = 'الكود يجب أن يكون 6 أرقام');
      return;
    }
    if (name.isEmpty) {
      setState(() => _errorMessage = 'أدخل اسمك');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final exists = await _firebaseService.groupExists(code);
      if (!exists) {
        setState(() => _errorMessage = 'هذا الكود غير موجود');
        return;
      }

      // Persist session so the user skips the form next launch.
      await _localStorage.saveSession(userName: name, groupCode: code);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(groupCode: code, userName: name),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[JoinGroup] ERROR: ${e.toString()}');
      debugPrint('[JoinGroup] STACK TRACE:\n$st');
      final msg = 'فشل في الانضمام: ${e.toString()}';
      setState(() => _errorMessage = msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.group_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'مرحباً بك في GlovoMate',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A237E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'أنشئ مجموعة أو انضم لمجموعة موجودة',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 36),

                // Name field
                TextField(
                  controller: _nameController,
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(
                    labelText: 'اسمك',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // Group code field
                TextField(
                  controller: _codeController,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: 'كود المجموعة',
                    counterText: '',
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                // Error message
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),

                const SizedBox(height: 8),

                // Create Group button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _createGroup,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_circle_outline),
                    label: const Text('إنشاء مجموعة جديدة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Join Group button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.tonalIcon(
                    onPressed: _isLoading ? null : _joinGroup,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('الانضمام للمجموعة'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
