import 'package:flutter/material.dart';
import 'package:rss_reader/src/app/reader_controller.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/types.dart';

/// Dialog for editing the AI provider configuration.
///
/// Loads the currently-stored value on open (defaults when unset), lets the
/// user edit or reset it, and persists via [ReaderController.setAiConfig].
class AiSettingsDialog extends StatefulWidget {
  const AiSettingsDialog({super.key, required this.controller});

  final ReaderController controller;

  @override
  State<AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<AiSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _endpointController = TextEditingController();
  final _modelController = TextEditingController();
  final _apiKeyController = TextEditingController();
  String _targetLanguage = 'zh';
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  static const _defaultEndpoint = 'https://api.openai.com/v1/chat/completions';
  static const _defaultModel = 'gpt-4o-mini';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await widget.controller.getAiConfig();
      if (!mounted) return;
      setState(() {
        _endpointController.text =
            config.endpoint == _defaultEndpoint ? '' : config.endpoint;
        _modelController.text = config.model == _defaultModel ? '' : config.model;
        _apiKeyController.text = config.apiKey;
        _targetLanguage = config.targetLanguage.isEmpty ? 'zh' : config.targetLanguage;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = _describeError(e);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final endpoint = _endpointController.text.trim();
      final model = _modelController.text.trim();
      await widget.controller.setAiConfig(
        AiConfig(
          endpoint: endpoint.isEmpty ? _defaultEndpoint : endpoint,
          model: model.isEmpty ? _defaultModel : model,
          apiKey: _apiKeyController.text.trim(),
          targetLanguage: _targetLanguage,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('AI settings saved.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _error = _describeError(e);
        });
      }
    }
  }

  void _resetToDefaults() {
    setState(() {
      _endpointController.text = '';
      _modelController.text = '';
      _apiKeyController.text = '';
      _targetLanguage = 'zh';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('AI settings'),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _endpointController,
                        enabled: !_isSaving,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Endpoint URL',
                          hintText: _defaultEndpoint,
                          helperText:
                              'OpenAI-compatible chat completions endpoint.',
                        ),
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) {
                            return null;
                          }
                          final uri = Uri.tryParse(trimmed);
                          if (uri == null ||
                              !uri.hasScheme ||
                              !uri.hasAuthority ||
                              (uri.scheme != 'http' && uri.scheme != 'https')) {
                            return 'Enter a valid http(s) URL, or leave blank for the default.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _modelController,
                        enabled: !_isSaving,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          hintText: _defaultModel,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _apiKeyController,
                        enabled: !_isSaving,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'API key',
                          helperText:
                              'Stored locally in the app database.',
                        ),
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) {
                            return 'An API key is required to use AI features.';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _save(),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _targetLanguage,
                        decoration: const InputDecoration(
                          labelText: 'Target language',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                          DropdownMenuItem(value: 'en', child: Text('English')),
                        ],
                        onChanged: _isSaving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => _targetLanguage = value);
                                }
                              },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        if (!_isLoading)
          TextButton(
            onPressed: _isSaving ? null : _resetToDefaults,
            child: const Text('Reset'),
          ),
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading || _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

String _describeError(Object error) {
  if (error is ReaderAppException) {
    return error.message;
  }
  return error.toString();
}
