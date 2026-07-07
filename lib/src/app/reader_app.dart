import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rss_reader/src/app/article_detail_view.dart';
import 'package:rss_reader/src/app/reader_controller.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/error.dart';
import 'package:rss_reader/src/rust/api/reader.dart';
import 'package:rss_reader/src/rust/api/types.dart';

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key, required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Rust RSS Reader',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0B6E99),
              brightness: Brightness.light,
            ).copyWith(
              secondary: const Color(0xFFCB6E17),
              tertiary: const Color(0xFFC86B0A),
            ),
            scaffoldBackgroundColor: const Color(0xFFF5F6F8),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0B6E99),
              brightness: Brightness.dark,
            ).copyWith(
              secondary: const Color(0xFFCB6E17),
              tertiary: const Color(0xFFC86B0A),
            ),
            useMaterial3: true,
          ),
          themeMode: controller.themeMode,
          home: ReaderHome(controller: controller),
        );
      },
    );
  }
}

class ReaderHome extends StatefulWidget {
  const ReaderHome({super.key, required this.controller});

  final ReaderController controller;

  @override
  State<ReaderHome> createState() => _ReaderHomeState();
}

class _ReaderHomeState extends State<ReaderHome> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          key: _scaffoldKey,
          drawer: _buildDrawer(controller),
          appBar: AppBar(
            leading: _shouldShowDrawer(context)
                ? IconButton(
                    tooltip: 'Open feeds',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    icon: const Icon(Icons.menu),
                  )
                : null,
            title: const Text('Rust RSS Reader'),
            actions: [
              IconButton(
                tooltip: 'Refresh feeds',
                onPressed: controller.isWorking ? null : _refreshFeeds,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Add feed',
                onPressed: controller.isWorking ? null : _showAddFeedDialog,
                icon: const Icon(Icons.add),
              ),
              PopupMenuButton<_ReaderMenuAction>(
                tooltip: 'More actions',
                onSelected: (action) => _handleMenuAction(action, controller),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _ReaderMenuAction.clearRead,
                    enabled:
                        controller.hasReadArticles && !controller.isWorking,
                    child: const Text('Clear read articles'),
                  ),
                  PopupMenuItem(
                    value: _ReaderMenuAction.removeFeed,
                    enabled:
                        controller.canRemoveSelectedFeed &&
                        !controller.isWorking,
                    child: const Text('Remove current feed'),
                  ),
                  PopupMenuItem(
                    value: _ReaderMenuAction.feedViewMode,
                    enabled:
                        controller.selectedFeed != null &&
                        !controller.isWorking,
                    child: const Text('Feed view mode'),
                  ),
                  PopupMenuItem(
                    value: _ReaderMenuAction.defaultViewMode,
                    enabled: !controller.isWorking,
                    child: const Text('Default view mode'),
                  ),
                  PopupMenuItem(
                    value: _ReaderMenuAction.themeMode,
                    enabled: !controller.isWorking,
                    child: const Text('Theme'),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: _shouldShowFab(context)
              ? FloatingActionButton(
                  tooltip: 'Add feed',
                  onPressed: controller.isWorking ? null : _showAddFeedDialog,
                  child: const Icon(Icons.add),
                )
              : null,
          body: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 1120) {
                    return Row(
                      children: [
                        SizedBox(
                          width: 280,
                          child: _FeedSidebar(
                            controller: controller,
                            onCloseRequested: null,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          flex: 4,
                          child: _ArticleListPane(
                            controller: controller,
                            splitDetail: true,
                            onOpenArticle: (articleId) {
                              _openArticle(articleId, pushRoute: false);
                            },
                            onAddFeed: _showAddFeedDialog,
                            onRefresh: _refreshFeeds,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          flex: 5,
                          child: _ArticleDetailPane(
                            controller: controller,
                            showToolbar: true,
                            onCopyLink: _copySelectedArticleLink,
                            onToggleStar: _toggleSelectedStar,
                            onToggleRead: _toggleSelectedRead,
                            onPreviousArticle: _selectPreviousArticle,
                            onNextArticle: _selectNextArticle,
                          ),
                        ),
                      ],
                    );
                  }

                  if (constraints.maxWidth >= 860) {
                    return Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: _ArticleListPane(
                            controller: controller,
                            splitDetail: true,
                            onOpenArticle: (articleId) {
                              _openArticle(articleId, pushRoute: false);
                            },
                            onAddFeed: _showAddFeedDialog,
                            onRefresh: _refreshFeeds,
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          flex: 5,
                          child: _ArticleDetailPane(
                            controller: controller,
                            showToolbar: true,
                            onCopyLink: _copySelectedArticleLink,
                            onToggleStar: _toggleSelectedStar,
                            onToggleRead: _toggleSelectedRead,
                            onPreviousArticle: _selectPreviousArticle,
                            onNextArticle: _selectNextArticle,
                          ),
                        ),
                      ],
                    );
                  }

                  return _ArticleListPane(
                    controller: controller,
                    splitDetail: false,
                    onOpenArticle: (articleId) {
                      _openArticle(articleId, pushRoute: true);
                    },
                    onAddFeed: _showAddFeedDialog,
                    onRefresh: _refreshFeeds,
                  );
                },
              ),
              if (controller.isWorking)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget? _buildDrawer(ReaderController controller) {
    if (!_shouldShowDrawer(context)) {
      return null;
    }
    return Drawer(
      child: SafeArea(
        child: _FeedSidebar(
          controller: controller,
          onCloseRequested: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  bool _shouldShowDrawer(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 1120;
  }

  bool _shouldShowFab(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 860;
  }

  Future<void> _showAddFeedDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final submittedUrl = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add RSS feed'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Feed URL',
                hintText: 'https://example.com/feed.xml',
              ),
              validator: (value) {
                final trimmed = value?.trim() ?? '';
                if (trimmed.isEmpty) {
                  return 'Enter a feed URL.';
                }
                final uri = Uri.tryParse(trimmed);
                if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                  return 'Enter a valid absolute URL.';
                }
                return null;
              },
              onFieldSubmitted: (_) {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(controller.text.trim());
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(controller.text.trim());
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (!mounted || submittedUrl == null) {
      return;
    }

    // P1a: discover feeds at the URL via Rust (fetch + auto-detect feed vs
    // HTML page). If the URL is already a feed, a single candidate is returned;
    // if it's an HTML page, the <link rel="alternate"> feed links are scanned.
    List<FeedCandidate> candidates;
    try {
      candidates = await widget.controller.discoverFeeds(submittedUrl);
    } catch (error) {
      if (mounted) {
        _showMessage(_describeError(error), isError: true);
      }
      return;
    }
    if (!mounted) {
      return;
    }

    if (candidates.isEmpty) {
      _showMessage('No feeds found at that URL.', isError: true);
      return;
    }

    String chosenUrl;
    if (candidates.length == 1) {
      chosenUrl = candidates.first.url;
    } else {
      final picked = await _pickFeedCandidate(candidates);
      if (!mounted || picked == null) {
        return;
      }
      chosenUrl = picked;
    }

    await _runGuarded(
      () => widget.controller.subscribeFeed(chosenUrl),
      successMessage: 'Feed added.',
    );
  }

  /// Shows a picker when auto-discovery finds multiple feeds on a page.
  Future<String?> _pickFeedCandidate(List<FeedCandidate> candidates) {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Choose a feed'),
          children: [
            for (final candidate in candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(candidate.url),
                child: ListTile(
                  dense: true,
                  title: Text(
                    candidate.title?.isNotEmpty == true
                        ? candidate.title!
                        : candidate.url,
                  ),
                  subtitle: Text(candidate.url),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _refreshFeeds() async {
    final summary = await _runGuardedResult(widget.controller.refreshFeeds);
    if (!mounted || summary == null) {
      return;
    }
    if (summary.failedFeeds > 0) {
      _showMessage(
        'Refreshed ${summary.refreshedFeeds} feeds, '
        '${summary.insertedArticles} new articles, '
        '${summary.failedFeeds} failed.',
      );
    } else {
      _showMessage(
        'Refreshed ${summary.refreshedFeeds} feeds, '
        '${summary.insertedArticles} new articles.',
      );
    }
  }

  Future<void> _handleMenuAction(
    _ReaderMenuAction action,
    ReaderController controller,
  ) async {
    switch (action) {
      case _ReaderMenuAction.clearRead:
        final confirmed = await _confirmAction(
          title: 'Clear read articles?',
          body: 'Read articles will be removed from local storage.',
          confirmLabel: 'Clear',
        );
        if (!confirmed) {
          return;
        }
        await _runGuarded(
          controller.clearReadArticles,
          successMessage: 'Read articles removed.',
        );
        return;
      case _ReaderMenuAction.removeFeed:
        final feed = controller.selectedFeed;
        if (feed == null) {
          return;
        }
        final confirmed = await _confirmAction(
          title: 'Remove ${feed.title}?',
          body: 'This also removes the feed articles saved locally.',
          confirmLabel: 'Remove',
        );
        if (!confirmed) {
          return;
        }
        await _runGuarded(
          controller.removeSelectedFeed,
          successMessage: 'Feed removed.',
        );
        return;
      case _ReaderMenuAction.feedViewMode:
        await _showFeedViewModeDialog(controller);
        return;
      case _ReaderMenuAction.defaultViewMode:
        await _showDefaultViewModeDialog(controller);
        return;
      case _ReaderMenuAction.themeMode:
        await _showThemeModeDialog(controller);
        return;
    }
  }

  Future<void> _showFeedViewModeDialog(ReaderController controller) async {
    final feed = controller.selectedFeed;
    if (feed == null) {
      return;
    }
    final selected = await _pickViewMode(
      title: 'View mode for ${feed.title}',
      current: feed.articleViewMode,
      includeGlobal: true,
    );
    if (selected == null || !mounted) {
      return;
    }
    await _runGuarded(
      () => controller.updateFeedViewMode(feed.id, selected),
      successMessage: 'Feed view mode updated.',
    );
  }

  Future<void> _showDefaultViewModeDialog(ReaderController controller) async {
    final selected = await _pickViewMode(
      title: 'Default view mode',
      current: controller.appDefaultViewMode,
      includeGlobal: false,
    );
    if (selected == null || !mounted) {
      return;
    }
    controller.appDefaultViewMode = selected;
    _showMessage('Default view mode updated.');
  }

  Future<void> _showThemeModeDialog(ReaderController controller) async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Theme'),
          children: [
            for (final mode in ThemeMode.values)
              ListTile(
                title: Text(_themeModeLabel(mode)),
                trailing: mode == controller.themeMode
                    ? const Icon(Icons.check)
                    : const SizedBox.shrink(),
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    controller.themeMode = selected;
  }

  Future<ArticleViewMode?> _pickViewMode({
    required String title,
    required ArticleViewMode current,
    required bool includeGlobal,
  }) {
    final modes = <ArticleViewMode>[
      if (includeGlobal) ArticleViewMode.global,
      ArticleViewMode.rendered,
      ArticleViewMode.webpage,
      ArticleViewMode.external_,
    ];
    return showDialog<ArticleViewMode>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(title),
          children: [
            for (final mode in modes)
              ListTile(
                title: Text(_viewModeLabel(mode)),
                subtitle: Text(_viewModeDescription(mode)),
                trailing: mode == current
                    ? const Icon(Icons.check)
                    : const SizedBox.shrink(),
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        );
      },
    );
  }

  Future<void> _openArticle(String articleId, {required bool pushRoute}) async {
    await _runGuarded(() async {
      await widget.controller.openArticle(articleId);
    });

    if (!mounted) {
      return;
    }

    // For external-mode feeds, opening an article means launching the system
    // browser instead of navigating to an in-app detail view.
    final article = widget.controller.selectedArticle;
    if (article != null &&
        widget.controller.effectiveViewModeForFeed(article.feedId) ==
            ArticleViewMode.external_) {
      final launched = await openInSystemBrowser(article.url);
      if (mounted && !launched) {
        _showMessage('Could not open the article in a browser.', isError: true);
      }
      return;
    }

    if (!pushRoute) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              return Scaffold(
                appBar: AppBar(
                  title: Text(widget.controller.currentViewTitle),
                  actions: [
                    IconButton(
                      tooltip: 'Previous article',
                      onPressed:
                          widget.controller.canSelectPreviousArticle
                              ? _selectPreviousArticle
                              : null,
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      tooltip: 'Next article',
                      onPressed:
                          widget.controller.canSelectNextArticle
                              ? _selectNextArticle
                              : null,
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                    IconButton(
                      tooltip: 'Copy link',
                      onPressed: _copySelectedArticleLink,
                      icon: const Icon(Icons.link),
                    ),
                    IconButton(
                      tooltip: 'Toggle star',
                      onPressed: _toggleSelectedStar,
                      icon: Icon(
                        widget.controller.selectedArticle?.isStarred ?? false
                            ? Icons.star
                            : Icons.star_outline,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Toggle read state',
                      onPressed: _toggleSelectedRead,
                      icon: Icon(
                        widget.controller.selectedArticle?.isRead ?? false
                            ? Icons.mark_email_unread_outlined
                            : Icons.mark_email_read_outlined,
                      ),
                    ),
                  ],
                ),
                body: _ArticleDetailPane(
                  controller: widget.controller,
                  showToolbar: false,
                  onCopyLink: _copySelectedArticleLink,
                  onToggleStar: _toggleSelectedStar,
                  onToggleRead: _toggleSelectedRead,
                  onPreviousArticle: _selectPreviousArticle,
                  onNextArticle: _selectNextArticle,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _toggleSelectedStar() async {
    await _runGuarded(
      widget.controller.toggleSelectedArticleStar,
      successMessage: 'Article updated.',
    );
  }

  Future<void> _toggleSelectedRead() async {
    final article = widget.controller.selectedArticle;
    if (article == null) {
      return;
    }
    await _runGuarded(
      () => widget.controller.setSelectedArticleRead(!article.isRead),
      successMessage: 'Read state updated.',
    );
  }

  Future<void> _selectPreviousArticle() async {
    await _runGuarded(() => widget.controller.selectAdjacentArticle(-1));
  }

  Future<void> _selectNextArticle() async {
    await _runGuarded(() => widget.controller.selectAdjacentArticle(1));
  }

  Future<void> _copySelectedArticleLink() async {
    final article = widget.controller.selectedArticle;
    if (article == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: article.url));
    if (!mounted) {
      return;
    }
    _showMessage('Article link copied.');
  }

  Future<void> _runGuarded(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      if (!mounted || successMessage == null) {
        return;
      }
      _showMessage(successMessage);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(_describeError(error), isError: true);
    }
  }

  Future<T?> _runGuardedResult<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      if (mounted) {
        _showMessage(_describeError(error), isError: true);
      }
      return null;
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }
}

class _FeedSidebar extends StatelessWidget {
  const _FeedSidebar({
    required this.controller,
    required this.onCloseRequested,
  });

  final ReaderController controller;
  final VoidCallback? onCloseRequested;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Feeds', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '${controller.feeds.length} feeds, ${controller.totalUnreadCount} unread',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _SidebarDestination(
                  label: 'All articles',
                  count: controller.totalUnreadCount,
                  selected:
                      controller.selectedFeedId == null &&
                      !controller.isShowingStarredOnly &&
                      !controller.isShowingUnreadOnly,
                  icon: Icons.article_outlined,
                  onTap: () {
                    controller.showAllArticles();
                    onCloseRequested?.call();
                  },
                ),
                _SidebarDestination(
                  label: 'Unread',
                  count: controller.totalUnreadCount,
                  selected:
                      controller.selectedFeedId == null &&
                      controller.isShowingUnreadOnly,
                  icon: Icons.mark_email_unread_outlined,
                  onTap: () {
                    controller.showUnreadArticles();
                    onCloseRequested?.call();
                  },
                ),
                _SidebarDestination(
                  label: 'Starred',
                  count: controller.starredCount,
                  selected:
                      controller.selectedFeedId == null &&
                      controller.isShowingStarredOnly,
                  icon: Icons.star_outline,
                  onTap: () {
                    controller.showStarredArticles();
                    onCloseRequested?.call();
                  },
                ),
                const SizedBox(height: 12),
                for (final feed in controller.feeds)
                  _SidebarDestination(
                    label: feed.title,
                    count: feed.unreadCount,
                    selected:
                        controller.selectedFeedId == feed.id &&
                        !controller.isShowingStarredOnly &&
                        !controller.isShowingUnreadOnly,
                    icon: Icons.rss_feed,
                    onTap: () {
                      controller.showFeed(feed.id);
                      onCloseRequested?.call();
                    },
                    subtitle: feed.description.isNotEmpty
                        ? _plainText(feed.description)
                        : null,
                    errorText: feed.lastError,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.label,
    required this.count,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.errorText,
  });

  final String label;
  final int count;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  final String? subtitle;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: errorText != null ? scheme.error : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (errorText != null && errorText!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          errorText!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _CountPill(count: count),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArticleListPane extends StatelessWidget {
  const _ArticleListPane({
    required this.controller,
    required this.splitDetail,
    required this.onOpenArticle,
    required this.onAddFeed,
    required this.onRefresh,
  });

  final ReaderController controller;
  final bool splitDetail;
  final ValueChanged<String> onOpenArticle;
  final Future<void> Function() onAddFeed;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasFeeds) {
      return _EmptyState(
        icon: Icons.rss_feed,
        title: 'No feeds yet',
        body:
            'Add an RSS or Atom feed URL to start building your reading list.',
        actionLabel: 'Add feed',
        actionIcon: Icons.add,
        onAction: onAddFeed,
      );
    }

    if (!controller.hasArticles) {
      return _EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No articles in this view',
        body: 'Refresh the selected feeds or switch filters.',
        actionLabel: 'Refresh',
        actionIcon: Icons.refresh,
        onAction: onRefresh,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.currentViewTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                controller.currentViewSubtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              itemCount: controller.articles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final article = controller.articles[index];
                final selected =
                    splitDetail && controller.selectedArticle?.id == article.id;
                return _ArticleListTile(
                  article: article,
                  selected: selected,
                  onTap: () => onOpenArticle(article.id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ArticleListTile extends StatelessWidget {
  const _ArticleListTile({
    required this.article,
    required this.selected,
    required this.onTap,
  });

  final ArticleListItem article;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: article.isRead
                            ? FontWeight.w500
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    article.isStarred ? Icons.star : Icons.circle,
                    size: article.isStarred ? 18 : 10,
                    color: article.isStarred
                        ? const Color(0xFFC86B0A)
                        : article.isRead
                        ? scheme.outline
                        : scheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    article.feedTitle,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    _formatTimestamp(article.publishedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _plainText(article.summary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleDetailPane extends StatelessWidget {
  const _ArticleDetailPane({
    required this.controller,
    required this.showToolbar,
    required this.onCopyLink,
    required this.onToggleStar,
    required this.onToggleRead,
    required this.onPreviousArticle,
    required this.onNextArticle,
  });

  final ReaderController controller;
  final bool showToolbar;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onToggleStar;
  final Future<void> Function() onToggleRead;
  final Future<void> Function() onPreviousArticle;
  final Future<void> Function() onNextArticle;

  @override
  Widget build(BuildContext context) {
    final article = controller.selectedArticle;
    if (article == null) {
      return const _DetailEmptyState();
    }

    final effectiveMode = controller.effectiveViewModeForFeed(article.feedId);

    // External mode never renders inline; the browser handles display.
    if (effectiveMode == ArticleViewMode.external_) {
      return _ExternalModeNotice(article: article);
    }

    final header = _ArticleDetailHeader(
      controller: controller,
      article: article,
      showToolbar: showToolbar,
      effectiveMode: effectiveMode,
      onCopyLink: onCopyLink,
      onToggleStar: onToggleStar,
      onToggleRead: onToggleRead,
      onPreviousArticle: onPreviousArticle,
      onNextArticle: onNextArticle,
    );

    if (effectiveMode == ArticleViewMode.webpage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: header,
          ),
          const Divider(height: 1),
          Expanded(
            child: ArticleDetailBody(
              article: article,
              effectiveMode: effectiveMode,
              feedTitle: controller.feedTitleFor(article.feedId),
              header: const SizedBox.shrink(),
              controller: controller,
            ),
          ),
        ],
      );
    }

    return ArticleDetailBody(
      article: article,
      effectiveMode: effectiveMode,
      feedTitle: controller.feedTitleFor(article.feedId),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, const SizedBox(height: 4)],
        ),
      ),
      controller: controller,
    );
  }
}

class _ArticleDetailHeader extends StatelessWidget {
  const _ArticleDetailHeader({
    required this.controller,
    required this.article,
    required this.showToolbar,
    required this.effectiveMode,
    required this.onCopyLink,
    required this.onToggleStar,
    required this.onToggleRead,
    required this.onPreviousArticle,
    required this.onNextArticle,
  });

  final ReaderController controller;
  final Article article;
  final bool showToolbar;
  final ArticleViewMode effectiveMode;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onToggleStar;
  final Future<void> Function() onToggleRead;
  final Future<void> Function() onPreviousArticle;
  final Future<void> Function() onNextArticle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showToolbar)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              IconButton.filledTonal(
                tooltip: 'Previous article',
                onPressed: controller.canSelectPreviousArticle
                    ? onPreviousArticle
                    : null,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              IconButton.filledTonal(
                tooltip: 'Next article',
                onPressed: controller.canSelectNextArticle
                    ? onNextArticle
                    : null,
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              IconButton.filledTonal(
                tooltip: 'Copy article link',
                onPressed: onCopyLink,
                icon: const Icon(Icons.link),
              ),
              IconButton.filledTonal(
                tooltip: article.isStarred ? 'Remove star' : 'Star article',
                onPressed: onToggleStar,
                icon: Icon(
                  article.isStarred ? Icons.star : Icons.star_outline,
                ),
              ),
              IconButton.filledTonal(
                tooltip: article.isRead ? 'Mark unread' : 'Mark read',
                onPressed: onToggleRead,
                icon: Icon(
                  article.isRead
                      ? Icons.mark_email_unread_outlined
                      : Icons.mark_email_read_outlined,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Open in browser',
                onPressed: () => openInSystemBrowser(article.url),
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
        if (showToolbar) const SizedBox(height: 20),
        Text(
          controller.feedTitleFor(article.feedId),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Text(article.title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (article.author.isNotEmpty)
              Text(article.author, style: theme.textTheme.bodyMedium),
            Text(
              _formatTimestamp(article.publishedAt),
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              article.isRead ? 'Read' : 'Unread',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(
          article.url,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _ExternalModeNotice extends StatelessWidget {
  const _ExternalModeNotice({required this.article});

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
                Icons.open_in_new,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                article.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'This feed opens articles in your browser.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
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

class _DetailEmptyState extends StatelessWidget {
  const _DetailEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chrome_reader_mode_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Select an article',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final IconData actionIcon;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text('$count', style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

enum _ReaderMenuAction {
  clearRead,
  removeFeed,
  feedViewMode,
  defaultViewMode,
  themeMode,
}

String _viewModeLabel(ArticleViewMode mode) {
  switch (mode) {
    case ArticleViewMode.global:
      return 'Follow default';
    case ArticleViewMode.rendered:
      return 'Rendered content';
    case ArticleViewMode.webpage:
      return 'In-app webpage';
    case ArticleViewMode.external_:
      return 'System browser';
  }
}

String _themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return 'Follow system';
    case ThemeMode.light:
      return 'Light';
    case ThemeMode.dark:
      return 'Dark';
  }
}

String _viewModeDescription(ArticleViewMode mode) {
  switch (mode) {
    case ArticleViewMode.global:
      return 'Use the app default view mode.';
    case ArticleViewMode.rendered:
      return 'Render feed article content in the app.';
    case ArticleViewMode.webpage:
      return 'Open the article URL in an embedded webpage.';
    case ArticleViewMode.external_:
      return 'Open the article in the system browser.';
  }
}

String _formatTimestamp(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) {
    return 'Unknown date';
  }
  final local = parsed.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

String _plainText(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _describeError(Object error) {
  if (error is AppError) {
    return switch (error) {
      AppError_NotFound(:final resource, :final id) =>
        '$resource not found: $id',
      AppError_InvalidInput(:final field0) => field0,
      AppError_Network(:final status, :final message) =>
        'Network error ($status): $message',
      AppError_FeedParse(:final message) => 'Could not parse feed: $message',
      AppError_Database(:final field0) => 'Database error: $field0',
      AppError_Io(:final field0) => 'I/O error: $field0',
      AppError_Unauthorized() => 'Unauthorized',
      AppError_Conflict(:final field0) => field0,
    };
  }
  if (error is ReaderError) {
    return error.message;
  }
  if (error is ReaderAppException) {
    return error.message;
  }
  return error.toString();
}
