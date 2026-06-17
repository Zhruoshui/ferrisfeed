import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rss_reader/src/app/reader_controller.dart';
import 'package:rss_reader/src/app/reader_repository.dart';
import 'package:rss_reader/src/rust/api/reader.dart';

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key, required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rust RSS Reader',
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF0B6E99),
              brightness: Brightness.light,
            ).copyWith(
              secondary: const Color(0xFFCB6E17),
              tertiary: const Color(0xFFC86B0A),
            ),
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
        useMaterial3: true,
      ),
      home: ReaderHome(controller: controller),
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

    await _runGuarded(() async {
      await widget.controller.addFeed(submittedUrl);
    }, successMessage: 'Feed added.');
  }

  Future<void> _refreshFeeds() async {
    final summary = await _runGuardedResult(widget.controller.refreshFeeds);
    if (!mounted || summary == null) {
      return;
    }
    _showMessage(
      'Refreshed ${summary.refreshedFeeds} feeds, ${summary.insertedArticles} new articles.',
    );
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
    }
  }

  Future<void> _openArticle(String articleId, {required bool pushRoute}) async {
    await _runGuarded(() async {
      await widget.controller.openArticle(articleId);
    });

    if (!mounted || !pushRoute) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.controller.currentViewTitle),
              actions: [
                IconButton(
                  tooltip: 'Copy link',
                  onPressed: _copySelectedArticleLink,
                  icon: const Icon(Icons.link),
                ),
                IconButton(
                  tooltip: 'Toggle star',
                  onPressed: _toggleSelectedStar,
                  icon: const Icon(Icons.star_outline),
                ),
                IconButton(
                  tooltip: 'Toggle read state',
                  onPressed: _toggleSelectedRead,
                  icon: const Icon(Icons.mark_email_read_outlined),
                ),
              ],
            ),
            body: _ArticleDetailPane(
              controller: widget.controller,
              showToolbar: false,
              onCopyLink: _copySelectedArticleLink,
              onToggleStar: _toggleSelectedStar,
              onToggleRead: _toggleSelectedRead,
            ),
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
                      !controller.isShowingStarredOnly,
                  icon: Icons.article_outlined,
                  onTap: () {
                    controller.showAllArticles();
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
                        !controller.isShowingStarredOnly,
                    icon: Icons.rss_feed,
                    onTap: () {
                      controller.showFeed(feed.id);
                      onCloseRequested?.call();
                    },
                    subtitle: feed.description.isNotEmpty
                        ? _plainText(feed.description)
                        : null,
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
  });

  final String label;
  final int count;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  final String? subtitle;

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
                Icon(icon, size: 20),
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
  });

  final ReaderController controller;
  final bool showToolbar;
  final Future<void> Function() onCopyLink;
  final Future<void> Function() onToggleStar;
  final Future<void> Function() onToggleRead;

  @override
  Widget build(BuildContext context) {
    final article = controller.selectedArticle;
    if (article == null) {
      return const _DetailEmptyState();
    }

    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showToolbar)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
          const SizedBox(height: 20),
          SelectableText(
            article.url,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          if (_plainText(article.summary).isNotEmpty) ...[
            Text(
              _plainText(article.summary),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
          ],
          Text(
            _detailContent(article),
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  String _detailContent(Article article) {
    final content = _plainText(article.content);
    if (content.isNotEmpty) {
      return content;
    }
    final summary = _plainText(article.summary);
    if (summary.isNotEmpty) {
      return summary;
    }
    return 'This article does not include body content in the feed payload.';
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

enum _ReaderMenuAction { clearRead, removeFeed }

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
  if (error is ReaderError) {
    return error.message;
  }
  if (error is ReaderAppException) {
    return error.message;
  }
  return error.toString();
}
