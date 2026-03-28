import 'package:flutter/material.dart';

import '../../models/llm_model_config.dart';

/// Dialog for entering a custom GGUF model URL.
class CustomModelDialog extends StatefulWidget {
  const CustomModelDialog({super.key});

  @override
  State<CustomModelDialog> createState() => _CustomModelDialogState();
}

class _CustomModelDialogState extends State<CustomModelDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  String? _urlError;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();

    if (url.isEmpty) {
      setState(() => _urlError = 'URL is required');
      return;
    }
    try {
      final parsed = LlmModelRegistry.inspectCustomDownloadUrl(url);
      final displayName = name.isNotEmpty ? name : parsed.suggestedName;
      Navigator.of(
        context,
      ).pop(LlmModelRegistry.custom(name: displayName, downloadUrl: url));
    } on ArgumentError catch (e) {
      setState(() => _urlError = e.message?.toString() ?? 'Invalid GGUF URL');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom GGUF Model'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste the direct download URL for any GGUF model file. '
            'You are responsible for model compatibility.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'GGUF Download URL',
              hintText: 'https://huggingface.co/.../model.gguf',
              border: const OutlineInputBorder(),
              isDense: true,
              errorText: _urlError,
            ),
            autocorrect: false,
            keyboardType: TextInputType.url,
            onChanged: (_) {
              if (_urlError != null) setState(() => _urlError = null);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Display Name (optional)',
              hintText: 'e.g. Phi-3 Mini',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Use Model')),
      ],
    );
  }
}
