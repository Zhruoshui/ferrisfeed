import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:rss_reader/src/app/reader_controller.dart';
import 'package:rss_reader/src/rust/api/reader.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Whether the current platform can host an in-app [WebViewWidget].
///
/// `webview_flutter` only ships platform implementations for Android and iOS.
/// On desktop (Linux/Windows/macOS) we fall back to a rendered view plus an
/// "open in browser" affordance instead of crashing on an unsupported
/// controller.
bool isInAppWebviewSupported() {
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Feed content is untrusted, so only `http`/`https` URLs may ever be handed to
/// an embedded webview or the system browser. Schemes such as `javascript:`,
/// `data:`, or `file:` would otherwise allow a malicious feed to execute code
/// or exfiltrate local files.
bool isSafeExternalUrl(Uri uri) =>
    uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');

/// Opens [url] in the system browser. Returns `false` when the URL is unsafe or
/// unparseable, or when the platform refused to launch it, so callers can
/// surface an error.
Future<bool> openInSystemBrowser(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !isSafeExternalUrl(uri)) {
    return false;
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Renders the body of an article according to its effective view mode.
///
/// `external` mode is handled by the caller before an article is shown, so
/// this widget only needs to cover `rendered` and `webpage`.
class ArticleDetailBody extends StatelessWidget {
  const ArticleDetailBody({
    super.key,
    required this.article,
    required this.effectiveMode,
    required this.feedTitle,
    required this.header,
    required this.controller,
  });

  final Article article;
  final ArticleViewMode effectiveMode;
  final String feedTitle;
  final ReaderController controller;

  /// Metadata header (feed title, article title, author, date, link) that is
  /// shown above rendered content. It is omitted for the webpage view so the
  /// embedded page can use the full pane.
  final Widget header;

  @override
  Widget build(BuildContext context) {
    if (effectiveMode == ArticleViewMode.webpage) {
      return _WebpageArticleView(article: article);
    }
    return _RenderedArticleView(
      article: article,
      header: header,
      controller: controller,
    );
  }
}

class _RenderedArticleView extends StatelessWidget {
  const _RenderedArticleView({
    required this.article,
    required this.header,
    required this.controller,
  });

  final Article article;
  final Widget header;
  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final html = _articleHtml(article);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseFontSize = theme.textTheme.bodyLarge?.fontSize ?? 16.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              if (html.isNotEmpty) _ReadingFontControls(controller: controller),
              if (html.isEmpty)
                Text(
                  'This article does not include body content in the feed payload.',
                  style: theme.textTheme.bodyLarge,
                )
              else
                HtmlWidget(
                  html,
                  onTapUrl: (url) => openInSystemBrowser(url),
                  onTapImage: (metadata) {
                    final src = metadata.sources.isNotEmpty
                        ? metadata.sources.first.url
                        : '';
                    if (src.isNotEmpty) {
                      _showImageDialog(context, src);
                    }
                  },
                  textStyle: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    fontSize: baseFontSize * controller.readingFontScale,
                  ),
                  customStylesBuilder: (element) =>
                      _customStyles(element, isDark),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Style overrides applied per element: code blocks get a themed background
  /// and monospace font, images get responsive sizing, and in dark mode any
  /// feed-supplied inline colors are neutralized so the text follows the
  /// theme.
  Map<String, String>? _customStyles(
    dom.Element element,
    bool isDark,
  ) {
    final tag = element.localName?.toLowerCase();
    if (tag == 'pre') {
      return {
        'background-color': isDark ? '#1e1e1e' : '#f5f5f5',
        'padding': '12px',
        'border-radius': '8px',
        'overflow-x': 'auto',
        'font-family': 'monospace',
        'color': isDark ? '#e0e0e0' : '#1a1a1a',
      };
    }
    if (tag == 'img') {
      return {
        'max-width': '100%',
        'height': 'auto',
        'border-radius': '8px',
      };
    }
    if (isDark) {
      final style = element.attributes['style'];
      if (style != null &&
          (style.contains('background') || style.contains('color'))) {
        return {
          'background-color': 'transparent',
          'color': 'inherit',
        };
      }
    }
    return null;
  }

  void _showImageDialog(BuildContext context, String src) {
    showDialog<void>(
      context: context,
      builder: (context) => _ImageZoomDialog(src: src),
    );
  }
}

/// Compact A-/A+/reset control row shown above rendered article content.
class _ReadingFontControls extends StatelessWidget {
  const _ReadingFontControls({required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = controller.readingFontScale;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton.filledTonal(
            tooltip: 'Decrease font size',
            onPressed: scale <= 0.8
                ? null
                : () => controller.readingFontScale = scale - 0.1,
            icon: const Icon(Icons.text_decrease),
          ),
          const SizedBox(width: 8),
          Text(
            '${(scale * 100).round()}%',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Increase font size',
            onPressed: scale >= 1.6
                ? null
                : () => controller.readingFontScale = scale + 0.1,
            icon: const Icon(Icons.text_increase),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Reset font size',
            onPressed: (scale - 1.0).abs() < 0.01
                ? null
                : () => controller.readingFontScale = 1.0,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
    );
  }
}

/// Full-screen dialog showing a tappable, zoomable image. Falls back to a
/// "open in browser" button when the network image cannot be decoded.
class _ImageZoomDialog extends StatelessWidget {
  const _ImageZoomDialog({required this.src});

  final String src;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          maxScale: 4.0,
          child: Image.network(
            src,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return _ImageErrorView(src: src);
            },
          ),
        ),
      ),
    );
  }
}

class _ImageErrorView extends StatelessWidget {
  const _ImageErrorView({required this.src});

  final String src;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.broken_image_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Text('Could not load the image.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              openInSystemBrowser(src);
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open in browser'),
          ),
        ],
      ),
    );
  }
}

/// Picks the richest available HTML payload for rendered display.
String _articleHtml(Article article) {
  final content = article.content.trim();
  if (content.isNotEmpty) {
    return content;
  }
  return article.summary.trim();
}

class _WebpageArticleView extends StatefulWidget {
  const _WebpageArticleView({required this.article});

  final Article article;

  @override
  State<_WebpageArticleView> createState() => _WebpageArticleViewState();
}

class _WebpageArticleViewState extends State<_WebpageArticleView> {
  WebViewController? _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _maybeInitController();
  }

  @override
  void didUpdateWidget(_WebpageArticleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.article.url != widget.article.url) {
      final uri = Uri.tryParse(widget.article.url);
      if (uri != null && isSafeExternalUrl(uri)) {
        _controller?.loadRequest(uri);
      }
    }
  }

  void _maybeInitController() {
    if (!isInAppWebviewSupported()) {
      return;
    }
    final uri = Uri.tryParse(widget.article.url);
    if (uri == null || !isSafeExternalUrl(uri)) {
      return;
    }
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final target = Uri.tryParse(request.url);
            if (target == null || !isSafeExternalUrl(target)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() => _isLoading = true);
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        ),
      )
      ..loadRequest(uri);
    _controller = controller;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return _WebpageFallback(article: widget.article);
    }
    return Stack(
      children: [
        WebViewWidget(controller: controller),
        if (_isLoading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

/// Shown when the in-app webview is unavailable (web/desktop) or the article
/// URL cannot be parsed. Offers a system-browser escape hatch.
class _WebpageFallback extends StatelessWidget {
  const _WebpageFallback({required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.public_off,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'In-app webpage view is not supported on this platform.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SelectableText(
                article.url,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => openInSystemBrowser(article.url),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in browser'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
