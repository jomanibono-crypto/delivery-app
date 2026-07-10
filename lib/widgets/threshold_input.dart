import 'package:flutter/material.dart';
import '../services/app_settings.dart';

class ThresholdInput extends StatefulWidget {
  final AppSettings appSettings;

  const ThresholdInput({super.key, required this.appSettings});

  @override
  State<ThresholdInput> createState() => _ThresholdInputState();
}

class _ThresholdInputState extends State<ThresholdInput> {
  late final TextEditingController _controller;
  String? _errorText;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.appSettings.proximityThreshold.toString(),
    );
    widget.appSettings.addListener(_onExternalChange);
  }

  @override
  void dispose() {
    widget.appSettings.removeListener(_onExternalChange);
    _controller.dispose();
    super.dispose();
  }

  void _onExternalChange() {
    if (!mounted) return;
    final current = widget.appSettings.proximityThreshold.toString();
    if (_controller.text.trim() != current) {
      _controller.text = current;
    }
  }

  Future<void> _save() async {
    final raw = _controller.text.trim();

    final value = int.tryParse(raw);
    if (value == null) {
      setState(() => _errorText = 'أدخل رقماً صحيحاً');
      return;
    }
    if (value <= 0) {
      setState(() => _errorText = 'يجب أن تكون القيمة أكبر من صفر');
      return;
    }
    if (value > 100000) {
      setState(() => _errorText = 'القيمة كبيرة جداً (الحد الأقصى 100كم)');
      return;
    }

    setState(() {
      _errorText = null;
      _saved = false;
    });

    await widget.appSettings.setProximityThreshold(value);

    if (mounted) {
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ الحد: $value متر'),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 2),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _saved = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.appSettings,
      builder: (context, _) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مسافة الإشعار عند اقتراب عضو',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          labelText: 'المسافة (بالمتر)',
                          hintText: 'مثال: 200',
                          errorText: _errorText,
                          suffixText: 'متر',
                          prefixIcon: const Icon(Icons.straighten_rounded),
                        ),
                        onSubmitted: (_) => _save(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: Icon(
                          _saved ? Icons.check_rounded : Icons.save_rounded,
                          size: 20,
                        ),
                        label: Text(_saved ? 'تم' : 'حفظ'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'الحد الحالي: ${widget.appSettings.proximityThreshold} متر',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
