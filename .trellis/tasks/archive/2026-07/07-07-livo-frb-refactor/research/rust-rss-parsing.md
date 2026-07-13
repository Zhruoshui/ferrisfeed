# Research: Rust crates for RSS/Atom feed parsing & feed auto-discovery

- **Query**: Compare `feed-rs` vs `rss`+`atom_syndication`+`syndication` vs rolling our own / `feedfinder`; evaluate feed-format coverage, `content:encoded`/`media:content`/enclosures, date normalization, relative-URL resolution, HTML sanitization, feed auto-discovery, HTTP fetching (reqwest mobile TLS), maturity. Recommend a parsing stack + discovery approach.
- **Scope**: mixed (external crate research + internal repo/Livo constraints)
- **Date**: 2026-07-07

## Repo constraints (load-bearing)

Current `rust/Cargo.toml` deps (FRB rev `254b193`, `crate-type = ["cdylib","staticlib"]`):

```toml
flutter_rust_bridge = { git = "...", rev = "254b193" }
chrono = { version = "0.4", features = ["serde"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
url = "2.5"
uuid = { version = "1.23", features = ["v4", "serde", "js"] }
```

Targets: android, ios, linux, macos, windows (web dropped). FRB config
(`flutter_rust_bridge.yaml`): `rust_input: crate::api`, `rust_root: rust/`,
`dart_output: lib/src/rust`. Existing `rust/src/api/reader.rs` is an in-memory
JSON-snapshot prototype (`Feed`, `Article`, `FeedDraft`) — to be replaced by a
real persisted model (see prd.md P0/P1).

### Livo reference (what we must reproduce)

- `doc/Livo/src/main/services/feed/rss-parser.ts` — JS `rss-parser` with
  `customFields.item`: `content:encoded`, `media:content`, `media:thumbnail`,
  `media:group`, `itunes:summary/subtitle/duration/image`, Atom `link` arrays.
  Custom `User-Agent` + `Accept: application/rss+xml, application/atom+xml, …`.
  Conditional GET via `ETag` / `Last-Modified` (returns null on 304).
- `rss-parser-lenient.ts` — strips invalid XML 1.0 control chars, fixes
  unclosed CDATA, broken entities, BOM, mismatched tags (regex-based, best-effort).
- `feed-utils.ts` — extracts `MediaItem[]` from `media:content` / `media:group` /
  Atom `rel="enclosure"` links / iTunes image+duration; picks best image from
  `srcset`/`data-src`; stores full HTML content (`content:encoded`).
- `feed-title-resolver.ts` — fetches feed/site HTML, regex-extracts `<title>`.
- Discovery (`discovery/`) — **no generic `<link rel=alternate>` HTML parser**;
  instead: RSSHub route matching, platform-specific APIs (Bilibili/YouTube/X/
  Instagram/WeChat), profile-URL → feed-URL resolution via regex on fetched HTML
  (e.g. `youtube-profile-resolver.ts` regex-extracts `channelId` from HTML).
  `discover-search.ts` calls `fetchAndParseFeed(feedUrl)` to validate a candidate.
- HTML sanitization for readability: `@mozilla/readability` + `dompurify` +
  `linkedom` (`services/entry/readability.ts`). Out of scope for P1 (deferred to P2).

---

## Findings

### Candidate 1 — `feed-rs` 2.4.0  (RECOMMENDED)

- **Repo**: https://github.com/feed-rs/feed-rs · **License**: MIT · **Edition** 2021
- **Description**: "A feed parser that handles Atom, RSS 2.0, RSS 1.0, RSS 0.x
  and JSON Feed" — auto-detects XML vs JSON and the feed format.
- **`FeedType` enum**: `Atom | JSON | RSS0 | RSS1 | RSS2` (full coverage).

#### Dependencies (feed-rs inner `Cargo.toml`)

```toml
chrono = { version = "0.4.45", features = ["serde"] }
mediatype = { version = "0.21.0", features = ["serde"] }
quick-xml = { version = "0.41.0", features = ["encoding"] }
regex = "1.12.4"
serde = { version = "1.0.228", features = ["derive"] }
serde_json = "1.0.150"
siphasher = "1.0.3"
url = { version = "2.5.8", features = ["serde"] }
uuid = { version = "1.23.4", features = ["v4"] }
ammonia = { version = "4.1.3", optional = true }   # behind "sanitize" feature
[features]
sanitize = ["dep:ammonia"]
```

**Key fit**: `chrono`, `serde`, `serde_json`, `url`, `uuid` are ALREADY in our
`Cargo.toml` (same major versions). feed-rs only ADDS `quick-xml`, `mediatype`,
`regex`, `siphasher`, and optional `ammonia`. No HTTP client dep — it parses
`&[u8]` / `BufRead`, fully decoupled from fetching.

#### Unified model (`feed_rs::model`)

`Feed` and `Entry` are the two top-level structs; format-specific fields are
normalized into a single schema. `parser::parse(bytes)` returns `Feed`.

`Entry` fields (15):
```
id: String, title: Option<Text>, updated: Option<DateTime<Utc>>,
authors: Vec<Person>, content: Option<Content>, links: Vec<Link>,
summary: Option<Text>, categories: Vec<Category>, contributors: Vec<Person>,
published: Option<DateTime<Utc>>, source: Option<String>, rights: Option<Text>,
media: Vec<MediaObject>, language: Option<String>, base: Option<String>
```

`Content`:
```
body: Option<String>, content_type: MediaTypeBuf,
length: Option<u64>, src: Option<Link>
```
- Has a `sanitize()` method (uses ammonia when the `sanitize` feature is on).

`MediaObject` (maps `media:group` + standalone `media:*`):
```
title: Option<Text>, content: Vec<MediaContent>, duration: Option<Duration>,
thumbnails: Vec<MediaThumbnail>, texts: Vec<MediaText>,
description: Option<Text>, community: Option<MediaCommunity>, credits: Vec<MediaCredit>
```

Also: `Link` (href, rel, hreflang, media_type, length, title), `Person`,
`Text` (content + content_type: text/html/xhtml), `Category`, `Generator`,
`Image`, `MediaThumbnail` (image + width/height), `MediaContent` (url +
content_type + height/width/duration/size).

#### `content:encoded` / `media:content` / enclosures (verified in source)

From `feed-rs/src/parser/rss2/mod.rs`:
- `(NS::Content, "encoded") => entry.content = handle_content_encoded(child)?`
  — `content:encoded` → `entry.content.body` (full HTML).
- `(NS::RSS, "enclosure") => handle_enclosure(...)` — enclosure → `MediaObject`
  / `MediaContent` (treated as MediaRSS).
- `media:content`, `media:thumbnail`, `media:group` → `MediaObject`.
- iTunes elements parsed.
- Comment in source (lines 206-213): "enclosure is treated as if it was a
  MediaRSS MediaContent element and wrapped in a MediaObject;
  content:encoded is mapped to the content field of an Entry."

This directly matches Livo's `feed-utils.ts` extraction semantics — porting the
media/content logic is mostly a schema-mapping exercise, not re-parsing.

#### Date normalization

`published` and `updated` are already `Option<DateTime<Utc>>` (chrono). feed-rs
parses RFC-822 (RSS2), RFC-3339 (Atom), W3C-DTF, and falls back gracefully
(`None` if invalid). RSS has no `updated` → feed-rs copies from `published` for
consistency. No manual date parsing needed.

#### Relative-URL resolution

feed-rs tracks `xml_base` through the XML tree (xml:base attribute) and exposes
`Entry.base: Option<String>`. Links/media URLs are parsed against `xml_base`
via the `url` crate (`util::parse_uri(&attr.value, element.xml_base.as_ref())`).
For residual relative URLs in HTML content bodies, use `url::Url::join()` / the
`base` field — `url` is already a dep.

#### Lenient parsing

feed-rs uses `quick-xml` (streaming, tolerant) with `encoding` feature. It is
generally more robust than `rss-parser`'s xml2js. Livo's hand-rolled
`rss-parser-lenient.ts` (control-char stripping, CDATA/entity/BOM fixes) is
largely unnecessary — quick-xml handles BOM/encoding and malformed streams
without crashing. Edge-case very-broken feeds may still need pre-processing, but
this is the exception.

#### Sanitization

Enable `features = ["sanitize"]` → `ParserBuilder::new().sanitize_content(true)`
runs `ammonia` on `content`/`summary`/`title` text. Alternatively call
`ammonia::clean(&html)` directly when rendering (gives full control over the
whitelist via `ammonia::Builder`). `ammonia` 4.1.3 is the Rust equivalent of
`dompurify` (html5ever-based, whitelist-based, re-exports `url`, supports
relative-URL rewriting via `UrlRelative`). Deep-dive deferred to P2 (readability).

### Candidate 2 — `rss` 2.1.0 + `atom_syndication` 0.12.9  (NOT recommended)

- **Repo**: https://github.com/rust-syndication/rss · License MIT/Apache-2.0
- `rss` 2.1.0: RSS 2.0 only (parse + serialize). Built on `quick-xml` 0.41.
  Optional features: `atom` (pulls `atom_syndication`), `builders`, `validation`
  (chrono+url+mime), `with-serde`.
- `atom_syndication` 0.12.9: Atom 1.0 only.
- Lower-level: you get `Channel`/`Item` (RSS) or `Feed`/`Entry` (Atom) structs
  with format-specific fields. No unified model — you write the dispatch +
  normalization yourself. No JSON Feed. No RSS 1.0/RDF.
- `content:encoded` / `media:content` are NOT first-class — they're "extensions".
  `rss` exposes `Item::extensions()` (a map of namespace → elements); you must
  manually walk `media:content`, `content:encoded`, iTunes, etc. This is exactly
  the fragile `customFields` plumbing Livo does in JS — we'd be porting that
  pain, not eliminating it.
- Use only if you need to *author/serialize* feeds (we don't — read-only reader).

### Candidate 3 — `syndication` 0.5.0  (STALE — reject)

- Umbrella crate re-exporting `rss` + `atom_syndication` behind a `Feed` enum.
- **Stale**: depends on `rss ^1.8.0` and `atom_syndication ^0.6.0` (current are
  2.1.0 / 0.12.x). Last meaningful release years ago. Still no JSON Feed / RSS 1.0.
- Provides nothing over `feed-rs` and carries dead transitive deps. Do not use.

### Candidate 4 — rolling our own  (NOT recommended)

- Reimplementing RSS2/Atom/RSS1/JSON-Feed parsing on top of `quick-xml` is
  high-effort, bug-prone (date formats, namespaces, relative URLs, media
  extensions), and reproduces what `feed-rs` already does with a large fixture
  test suite. No upside for a read-only reader.

---

## Feed auto-discovery

Livo has NO standard `<link rel="alternate" type="application/rss+xml">` scanner
(its discovery is RSSHub-route + platform-API + regex-HTML). For a general RSS
reader we still want classic auto-discovery: fetch a URL, if HTML scan for feed
`<link>`s, if already a feed parse it. Two Rust options:

### `feedfinder` 0.4.0

- **Repo**: https://github.com/wezm/feedfinder · License MIT · Edition 2018.
- API: `detect_feeds(html: &str, url: &Url) -> Vec<FeedLink>`. Finds feeds via
  `<link rel=alternate type=application/rss+xml>` AND `<a href=*.rss>` tags.
- **Dependency concern**: depends on `kuchiki = "0.8"` — kuchiki is
  **unmaintained/deprecated** (folded into `scraper`). `url = ">=1.7,<3"`.
  Edition 2018 + dead HTML parser = likely maintenance risk and possible
  compile friction with a modern toolchain.
- Verdict: conceptually exactly right, but the kuchiki dependency makes it a
  liability. Prefer `scraper` + a ~30-line custom `detect_feeds` (see below).

### `scraper` 0.27.0  (RECOMMENDED for discovery HTML parsing)

- **Repo**: https://github.com/causal-agent/scraper · HTML parsing + CSS-selector
  querying on Servo's `html5ever` + `selectors`. Deps: `cssparser`, `html5ever`,
  `selectors` (all actively maintained, browser-grade).
- API: `Html::parse_document(html)` then `Selector::parse("link[rel=alternate]")`.
- This is the idiomatic, maintained way to scan HTML for feed links. A minimal
  discovery fn:

```rust
use scraper::{Html, Selector};
use url::Url;

pub fn discover_feed_links(html: &str, base: &Url) -> Vec<Url> {
    let doc = Html::parse_document(html);
    let sel = Selector::parse("link[rel~='alternate'][type*='rss'], \
                               link[rel~='alternate'][type*='atom'], \
                               link[rel~='alternate'][type*='json']").unwrap();
    doc.select(&sel).filter_map(|e| e.value().attr("href"))
        .filter_map(|h| base.join(h).ok()).collect()
}
```

- Mirrors what MrRSS's Go reference does with `goquery`
  (`doc/MrRSS/internal/discovery/html_parser.go`), and is a superset of Livo's
  regex approach. `scraper` is also reusable for future readability/extraction.

### Manual `html` (the `html` crate) — note

There is an older `html` crate, but `scraper` (html5ever) is the maintained,
spec-compliant choice. Don't confuse with Dart-side `html` (already in
`pubspec.yaml`) — that's for Flutter rendering, not Rust discovery.

---

## HTTP fetching in Rust — `reqwest` 0.13.x

### TLS backend (mobile-critical)

`reqwest` 0.13.x **default TLS is now `rustls`** (not native-tls). From
`reqwest/Cargo.toml`:

```toml
default = ["default-tls", "charset", "http2", "system-proxy"]
default-tls = ["rustls"]                       # <-- rustls is default
rustls = ["__rustls-aws-lc-rs", "dep:rustls-platform-verifier", "__rustls"]
rustls-no-provider = ["dep:rustls-platform-verifier", "__rustls"]  # bring-your-own crypto
native-tls = ["__native-tls", "__native-tls-alpn"]
native-tls-vendored = ["__native-tls", "native-tls-crate?/vendored", ...]
```

- **`rustls` (default)** uses `aws-lc-rs` as the crypto provider (C/asm, compiles
  on android/ios/linux/macos/windows) **plus `rustls-platform-verifier`**, which
  delegates certificate validation to the OS trust store (Android Keystore, iOS
  Keychain, macOS system roots, Windows cert store). This is the best choice for
  mobile: no OpenSSL to cross-compile, native cert trust like a browser.
- **`native-tls`/`native-tls-vendored`** would require shipping/building OpenSSL
  on Android (painful NDK cross-compile). Avoid unless a specific need arises.
- **`rustls-no-provider`** lets you plug in `ring` instead of `aws-lc-rs` if
  `aws-lc-rs` ever has a build issue on a target; default `aws-lc-rs` is fine for
  all five of our targets today.
- reqwest is already in the local cargo cache (0.12.x and 0.13.2), so the
  ecosystem is familiar and dependency resolution is quick.

### Async + FRB

reqwest is async (tokio). FRB supports async Rust functions (return `Future`),
which map to Dart `Future`s — do NOT mark network calls `#[frb(sync)]` (the
current `reader.rs` uses sync for in-memory ops only; network must be async to
avoid blocking the UI isolate). For sync-progress events (Livo streams refresh
progress), use FRB `StreamSink<T>` (the generated code already shows
`default_stream_sink_codec = SseCodec`). A tokio runtime is required — FRB's
default handler can host it, or run an explicit `#[tokio::main]`-style runtime
inside the Rust lib init (`init_app()` already exists in `simple.rs`).

### Recommended reqwest config

```toml
reqwest = { version = "0.13", default-features = false, features = [
  "rustls-tls", "charset", "http2", "system-proxy", "gzip", "brotli"
] }
```
(or simply rely on `default` which is `rustls`-based). Add `json` only if needed
(not required — feed-rs parses bodies, and serde_json is already a dep).

Conditional GET (ETag / If-None-Match, Last-Modified / If-Modified-Since) is
just request-builder headers — mirrors Livo's `FetchFeedOptions.etag` /
`lastModified`. 304 → return `NotModified` (no re-parse).

---

## Maturity & maintenance summary

| Crate | Version | Status | Notes |
|---|---|---|---|
| `feed-rs` | 2.4.0 | Active, mature | Large fixture test suite, handles all 5 formats, optional sanitize. Deps align with ours. |
| `rss` | 2.1.0 | Maintained | RSS2-only; extensions are manual. Good for authoring. |
| `atom_syndication` | 0.12.9 | Maintained | Atom-only; pulled by `rss`'s `atom` feature. |
| `syndication` | 0.5.0 | **Stale** | Pins old rss/atom; no JSON Feed. Reject. |
| `feedfinder` | 0.4.0 | Low activity | Correct idea, but `kuchiki 0.8` (dead) dep. Risky. |
| `scraper` | 0.27.0 | Active | html5ever + selectors; idiomatic HTML querying. |
| `reqwest` | 0.13.x | Active, standard | Default rustls + platform-verifier; mobile-friendly. |
| `ammonia` | 4.1.3 | Active | html5ever whitelist sanitizer (dompurify analog). |

---

## Recommendation

### Parsing stack

```toml
# add to rust/Cargo.toml [dependencies]
feed-rs = { version = "2.4", features = ["sanitize"] }
reqwest = { version = "0.13", default-features = false, features = [
    "rustls-tls", "charset", "http2", "system-proxy", "gzip", "brotli"
] }
# tokio runtime for reqwest (FRB async)
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
```

- **`feed-rs`** as the sole feed parser: one `parser::parse(&bytes)` entry point,
  unified `Feed`/`Entry` model, `content:encoded` → `entry.content.body`,
  `media:*`/`enclosure` → `entry.media` (`MediaObject`), dates already
  `DateTime<Utc>`, `base`/`xml_base` for relative-URL resolution via `url`.
  This replaces Livo's `rss-parser` + `rss-parser-lenient` + `feed-utils`
  extraction with a single well-tested crate whose deps overlap our existing
  `chrono`/`serde`/`serde_json`/`url`/`uuid`.
- **`reqwest`** (rustls default) for HTTP: async, mobile-native cert trust via
  `rustls-platform-verifier`, conditional-GET headers, gzip/brotli. Decoupled
  from feed-rs (fetch bytes → hand to `feed-rs`).
- **`ammonia`** comes transitively via feed-rs's `sanitize` feature; also usable
  directly at render time for finer whitelist control (deferred to P2).

### Discovery approach

- Use **`scraper`** + a small custom `discover_feed_links(html, base_url)` that
  selects `link[rel~="alternate"]` with `type` containing `rss`/`atom`/`json`,
  resolves hrefs against the page URL with `url::Url::join`, and returns ranked
  candidates. Then probe each candidate by fetching + `feed-rs::parse` to confirm
  it's a real feed (mirrors Livo's `fetchAndParseFeed` validation step).
- Do NOT adopt `feedfinder` due to its unmaintained `kuchiki` dependency; the
  scraper function is ~30 lines and gives full control.
- For Livo's platform-specific discovery (RSSHub routes, Bilibili/YouTube/X/
  Instagram APIs): that's P3 (out of scope now) — but the `scraper` + `reqwest`
  + `feed-rs` trio is the foundation those will build on (e.g. YouTube
  `channelId` regex extraction over `scraper`-parsed HTML instead of raw regex).
- OPML import/export (P3) is orthogonal to feed parsing — `feed-rs` doesn't do
  OPML; Livo has its own `opml-parser.ts`. Port separately if needed.

### FRB bridge shape (informs the parsing API)

- Expose async (non-`#[frb(sync)]`) Rust fns: `async fn fetch_and_parse_feed(url, etag, last_modified) -> Result<FeedSnapshot, ReaderError>`.
- `FeedSnapshot` maps `feed_rs::model::Feed` → our `Feed`/`Article` FRB structs
  (the existing `reader.rs` `Feed`/`Article` shapes are already close; add
  `media`, `author`, `categories` as needed).
- Stream sync progress via `StreamSink<SyncEvent>` (FRB generated SseCodec).
- Keep `feed-rs`/`reqwest` types INTERNAL (not exposed across the bridge) —
  convert to plain FRB-compatible structs to avoid codegen friction with
  `MediaTypeBuf`/`quick-xml` types.

## Caveats / Not found

- `feed-rs` does not fetch HTTP itself — by design. Some older docs/examples
  reference a `feed-rs` `util`/reqwest helper; current 2.4.0 has none (parse
  only). This is the correct separation.
- `aws-lc-rs` (reqwest's default rustls provider) builds from C/assembly; if a
  future target (e.g. a specific iOS simulator) has issues, fall back to
  `rustls-no-provider` + `ring`. Not observed as a problem for our 5 targets.
- `kuchiki` (feedfinder's dep) is confirmed unmaintained; if a maintained fork
  of `feedfinder` appears, reconsider — but `scraper` is the lower-risk path now.
- Did not benchmark `feed-rs` vs `rss` parse speed; `feed-rs` uses the same
  `quick-xml` 0.41 as `rss`, so throughput is comparable and not a concern for a
  client-side reader.
- HTML sanitization deep-dive (ammonia whitelist tuning, readability extraction)
  deliberately deferred to P2 per prd.md scope.
