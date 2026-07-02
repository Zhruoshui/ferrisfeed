import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
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
  });

  final Article article;
  final ArticleViewMode effectiveMode;
  final String feedTitle;

  /// Metadata header (feed title, article title, author, date, link) that is
  /// shown above rendered content. It is omitted for the webpage view so the
  /// embedded page can use the full pane.
  final Widget header;

  @override
  Widget build(BuildContext context) {
    if (effectiveMode == ArticleViewMode.webpage) {
      return _WebpageArticleView(article: article);
    }
    return _RenderedArticleView(article: article, header: header);
  }
}

class _RenderedArticleView extends StatelessWidget {
  const _RenderedArticleView({required this.article, required this.header});

  final Article article;
  final Widget header;

  @override
  Widget build(BuildContext context) {
    final html = _articleHtml(article);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          if (html.isEmpty)
            Text(
              'This article does not include body content in the feed payload.',
              style: Theme.of(context).textTheme.bodyLarge,
            )
          else
            HtmlWidget(
              html,
              onTapUrl: (url) => openInSystemBrowser(url),
              textStyle: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.5),
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
