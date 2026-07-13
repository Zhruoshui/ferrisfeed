import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:rss_reader/src/rust/api/types.dart';

/// Renders the AI-generated content panel inside the article detail view.
///
/// Shows segmented Original/Summary/Translation controls and the corresponding
/// content. Handles loading and error states inline.
class AiPanel extends StatelessWidget {
  const AiPanel({
    super.key,
    required this.entry,
    required this.mode,
    required this.loading,
    required this.error,
    required this.cachedSummary,
    required this.cachedTranslation,
    required this.onSummarize,
    required this.onTranslate,
    required this.onSwitchMode,
  });

  final Entry entry;
  final AiViewMode mode;
  final bool loading;
  final String? error;
  final String? cachedSummary;
  final String? cachedTranslation;
  final VoidCallback onSummarize;
  final VoidCallback onTranslate;
  final ValueChanged<AiViewMode> onSwitchMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<AiViewMode>(
                    segments: const [
                      ButtonSegment(
                        value: AiViewMode.original,
                        label: Text('Original'),
                      ),
                      ButtonSegment(
                        value: AiViewMode.summary,
                        label: Text('Summary'),
                      ),
                      ButtonSegment(
                        value: AiViewMode.translation,
                        label: Text('Translation'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: loading
                        ? null
                        : (values) => onSwitchMode(values.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (mode == AiViewMode.summary) ...[
              _AiActionRow(
                label: 'AI summary',
                actionLabel: 'Summarize',
                onAction: onSummarize,
                loading: loading,
              ),
              const SizedBox(height: 8),
              _AiContentBody(
                text: cachedSummary ?? entry.aiSummary,
                emptyMessage:
                    'Tap Summarize to generate a concise summary of this article.',
                error: error,
              ),
            ] else if (mode == AiViewMode.translation) ...[
              _AiActionRow(
                label: 'AI translation',
                actionLabel: 'Translate',
                onAction: onTranslate,
                loading: loading,
              ),
              const SizedBox(height: 8),
              _AiContentBody(
                text: cachedTranslation ?? entry.aiTranslationZh,
                emptyMessage:
                    'Tap Translate to translate this article into Simplified Chinese.',
                error: error,
              ),
            ] else ...[
              _AiInfoText(
                'Reading the original article. Use the buttons above to switch '
                'to an AI summary or translation.',
                theme: theme,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiActionRow extends StatelessWidget {
  const _AiActionRow({
    required this.label,
    required this.actionLabel,
    required this.onAction,
    required this.loading,
  });

  final String label;
  final String actionLabel;
  final VoidCallback onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        if (loading)
          const SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          FilledButton.tonal(
            onPressed: onAction,
            child: Text(actionLabel),
          ),
      ],
    );
  }
}

class _AiContentBody extends StatelessWidget {
  const _AiContentBody({
    required this.text,
    required this.emptyMessage,
    this.error,
  });

  final String? text;
  final String emptyMessage;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (error != null) {
      return _AiInfoText(error!, theme: theme, isError: true);
    }
    final value = text;
    if (value == null || value.trim().isEmpty) {
      return _AiInfoText(emptyMessage, theme: theme);
    }
    final html = _toHtmlParagraphs(value);
    return HtmlWidget(
      html,
      textStyle: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
    );
  }

  /// Wraps plain text in `<p>` tags so [HtmlWidget] renders paragraphs.
  static String _toHtmlParagraphs(String text) {
    final paragraphs = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) {
      return '<p>${text.trim()}</p>';
    }
    return paragraphs.map((p) => '<p>$p</p>').join('\n');
  }
}

class _AiInfoText extends StatelessWidget {
  const _AiInfoText(
    this.text, {
    required this.theme,
    this.isError = false,
  });

  final String text;
  final ThemeData theme;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: isError ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
