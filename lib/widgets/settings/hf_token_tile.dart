import 'package:flutter/material.dart';

import '../../constants/llm_strings.dart';
import '../../services/hf_token_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/koshika_design_system.dart';

/// Token input tile with save/clear and an info banner about common issues.
class HfTokenTile extends StatefulWidget {
  const HfTokenTile({super.key});

  @override
  State<HfTokenTile> createState() => _HfTokenTileState();
}

class _HfTokenTileState extends State<HfTokenTile> {
  final _controller = TextEditingController();
  bool _hasToken = false;
  bool _obscured = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await HfTokenService.getToken();
    if (mounted) {
      setState(() {
        _hasToken = token != null;
        if (token != null) _controller.text = token;
        _loading = false;
      });
    }
  }

  Future<void> _saveToken() async {
    final token = _controller.text.trim();
    if (token.isEmpty) return;
    await HfTokenService.setToken(token);
    if (mounted) {
      setState(() => _hasToken = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(LlmStrings.hfTokenSaved)));
    }
  }

  Future<void> _clearToken() async {
    await HfTokenService.setToken(null);
    if (mounted) {
      setState(() {
        _hasToken = false;
        _controller.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(LlmStrings.hfTokenCleared)));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(KoshikaSpacing.base),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: KoshikaSpacing.xs),
      child: Material(
        color: AppColors.surfaceContainerLowest,
        borderRadius: KoshikaRadius.lg,
        child: Padding(
          padding: const EdgeInsets.all(KoshikaSpacing.base),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Description
              Text(
                LlmStrings.hfTokenDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: KoshikaSpacing.md),

              // Token input
              TextField(
                controller: _controller,
                obscureText: _obscured,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: LlmStrings.hfTokenFieldLabel,
                  hintText: LlmStrings.hfTokenFieldHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscured ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  ),
                ),
              ),
              const SizedBox(height: KoshikaSpacing.sm),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_hasToken)
                    TextButton(
                      onPressed: _clearToken,
                      child: const Text(LlmStrings.hfTokenClearButton),
                    ),
                  const SizedBox(width: KoshikaSpacing.sm),
                  FilledButton.tonal(
                    onPressed: _saveToken,
                    child: const Text(LlmStrings.hfTokenSaveButton),
                  ),
                ],
              ),
              const SizedBox(height: KoshikaSpacing.md),

              // Info banner
              Container(
                padding: const EdgeInsets.all(KoshikaSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: KoshikaRadius.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: KoshikaSpacing.sm),
                    Expanded(
                      child: Text(
                        LlmStrings.hfTokenInfoMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
