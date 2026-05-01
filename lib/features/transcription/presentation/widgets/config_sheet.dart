import 'package:flutter/material.dart';

import '../../data/models/session_config.dart';

/// Bottom sheet for adjusting per-session config — custom Gemini prompt and
/// model name. Mirrors the React frontend's "Configure prompt" sidebar.
class ConfigSheet extends StatefulWidget {
  const ConfigSheet({
    super.key,
    required this.initial,
    required this.onSave,
  });

  final SessionConfig initial;
  final ValueChanged<SessionConfig> onSave;

  static Future<void> show(
    BuildContext context, {
    required SessionConfig initial,
    required ValueChanged<SessionConfig> onSave,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: ConfigSheet(initial: initial, onSave: onSave),
      ),
    );
  }

  @override
  State<ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends State<ConfigSheet> {
  late final TextEditingController _promptCtrl =
      TextEditingController(text: widget.initial.customPrompt ?? '');
  late final TextEditingController _modelCtrl =
      TextEditingController(text: widget.initial.modelName ?? '');

  @override
  void dispose() {
    _promptCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session configuration', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Optional overrides applied at the start of the next recording.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text('Custom prompt', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _promptCtrl,
              maxLines: 8,
              minLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText:
                    'e.g. Format the note as SOAP and include red-flag findings prominently.',
              ),
            ),
            const SizedBox(height: 18),
            Text('Gemini model (advanced)',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                hintText: 'gemini-2.5-pro (default) / gemini-2.5-flash',
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      widget.onSave(SessionConfig(
                        customPrompt: _promptCtrl.text.trim().isEmpty
                            ? null
                            : _promptCtrl.text.trim(),
                        modelName: _modelCtrl.text.trim().isEmpty
                            ? null
                            : _modelCtrl.text.trim(),
                      ));
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
