# Component Guidelines

> How components are built in this project.

---

## Overview

<!--
Document your project's component conventions here.

Questions to answer:
- What component patterns do you use?
- How are props defined?
- How do you handle composition?
- What accessibility standards apply?
-->

(To be filled by the team)

---

## Component Structure

<!-- Standard structure of a component file -->

(To be filled by the team)

---

## Props Conventions

<!-- How props should be defined and typed -->

(To be filled by the team)

---

## Styling Patterns

<!-- How styles are applied (CSS modules, styled-components, Tailwind, etc.) -->

(To be filled by the team)

---

## Accessibility

<!-- A11y requirements and patterns -->

(To be filled by the team)

---

## Common Mistakes

<!-- Component-related mistakes your team has made -->

### Don't: Feed URLs into WebView / browser / launcher without a scheme guard

**Problem**: RSS/Atom feed content is **untrusted input**. The Rust
`normalize_url` accepts any scheme `Url::parse` recognizes, so `javascript:`,
`data:`, and `file:` URLs flow through to Flutter unchanged. Handing them
straight to `url_launcher`, a `WebViewController.loadRequest`, or a WebView
in-page navigation lets a malicious feed execute script or read local files
(the WebView runs with `JavaScriptMode.unrestricted`).

```dart
// Bad — launches whatever scheme the feed provided
await launchUrl(Uri.parse(article.url));
controller.loadRequest(Uri.parse(article.url));
```

**Instead**: Gate every URL entry point (system browser launch, initial
WebView load, `didUpdateWidget` reload, and the `onNavigationRequest`
delegate) on an http/https allow-list:

```dart
bool isSafeExternalUrl(Uri uri) =>
    uri.scheme == 'http' || uri.scheme == 'https';

// launcher / loadRequest
if (uri != null && isSafeExternalUrl(uri)) { /* proceed */ }

// WebView navigation delegate — block scheme pivots mid-session
onNavigationRequest: (request) {
  final target = Uri.tryParse(request.url);
  if (target == null || !isSafeExternalUrl(target)) {
    return NavigationDecision.prevent;
  }
  return NavigationDecision.navigate;
},
```

**Why**: `normalize_url` on the Rust side is *normalization*, not a security
filter. The safe-scheme check must live at the Flutter consumption boundary,
and it must cover **all four** entry points — a guard on the launcher alone
still leaves the WebView open to a `file:`/`javascript:` in-page link.

**Rendered HTML**: `flutter_widget_from_html`'s `HtmlWidget` does not execute
embedded `<script>` by default, so rendering untrusted feed HTML is safe — but
its link taps must still route through the scheme-guarded launcher, not a raw
`launchUrl`.

**Tests Required**: assert `isSafeExternalUrl` accepts `http`/`https` and
rejects `javascript:`, `data:`, `file:`, and relative URLs.

---

### Gotcha: FRB enum variant `external` becomes `external_` in Dart

The Rust `ArticleViewMode::External` variant generates as
`ArticleViewMode.external_` in Dart because `external` is a Dart reserved
keyword. When matching on generated FRB enums, watch for trailing-underscore
renames on any variant whose name collides with a Dart keyword (`external`,
`default`, `in`, `is`, etc.).

