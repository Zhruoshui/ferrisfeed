# Livo reference: discovery & special feeds

Findings from `doc/Livo/` (via CodeGraph), used to confirm/refine the P3 ADR.
The original research subagent died (transcript cleaned up) before reporting, so
this is a direct CodeGraph pass focused on the architecture-deciding pieces.

## 1. OPML import/export — `doc/Livo/src/main/services/feed/opml-parser.ts`

- `OPMLFeed { title, xmlUrl, htmlUrl?, category? }` — `xmlUrl` is the RSS URL,
  `htmlUrl` the site URL, `category` the nested folder.
- `parseOPML(xml, options)` is a **hand-rolled tag-by-tag state machine** (not a
  library) that walks `<outline>` tokens with a category stack, supporting
  arbitrary nesting. Has DoS limits: `maxFeeds=1000`, `maxOutlineTags=10000`,
  `maxCategoryDepth=32`, `maxAttributeTextLength=2048`, throwing
  `OPMLParseLimitError`.
- Import UX (`renderer/.../settings/OpmlImportProgress.tsx`): after import, a
  background refresh runs; auto-refresh is capped at 8 feeds, larger batches get
  a "refresh manually" hint.

**Implication for us**: We use the Rust `opml` crate (ADR #4) instead of
hand-rolling — simpler, spec-compliant. But borrow Livo's **field mapping**
(title/xmlUrl/htmlUrl/category) and the **DoS-limit philosophy** + the
"cap auto-refresh after large import" UX at P3a.

## 2. Special feeds / RSSHub — `doc/Livo/src/main/services/feed/feed-source-provider.ts`

- Livo has **no "provider trait"**. Special feeds are handled by
  `getNormalizedFeedUrl(feed)`:
  - if `feed.upstreamUrl` is set (the special source's generated URL) -> use it;
  - else `normalizeFeedUrl(feed.url, rsshubInstance)` where
    `rsshubInstance = settings.general.rsshubInstance || DEFAULT_RSSHUB_INSTANCE`.
- `getFeedKey` recognizes special sources by URL pattern: bilibili
  (`/bilibili/user/dynamic/:uid`), instagram, twitter. So **Bilibili/Instagram/
  Twitter are RSSHub routes** stored as the feed URL.
- WeChat-MP: `rewriteWechatMpFeedUrlToBackendProxy(...)` — WeChat feed URLs are
  rewritten to a backend proxy (WeChat has no public RSS + anti-scraping; Livo
  proxies via its own backend / a bridge).
- Livo also has a complex aggregator (direct / local-agent / private-aggregator
  / server-cache) for high-risk feeds (`isHighRiskFeed`, `classifyFeedRoute`).
  This is an advanced reliability layer we do NOT need for MVP — direct fetch
  suffices.

**Implication for us**: Confirms ADR #2 (provider abstraction) is a *refinement*
of Livo's approach: Livo stuffs special-source logic into a normalize function +
`upstreamUrl` field; we make it an explicit `SpecialFeedProvider` trait +
registry (clearer, unit-testable, easier to add Bilibili/WeChat later). The
`upstreamUrl` concept maps to our generated `source_url`; our `provider_input`
(= original channel/route) is the extra that lets us rebuild URLs when the
RSSHub base changes (Livo stores the final URL and would orphan on base change).
WeChat-MP via a pure RSSHub route may be unreliable (Livo needed a backend
proxy) — note for the follow-up WeChat sub-task.

## 3. Settings — `settingsProvider` (electron-store)

- Livo stores config in a structured settings object: `settings.general.
  rsshubInstance` (RSSHub base URL), `settings.aggregator` (mode, cache
  retention, poll interval).

**Implication for us**: Confirms ADR #3 — we use a generic `settings(key,value)`
table with `rsshub.base_url`; same idea, Rust-persisted.

## 4. Schema impact — Feed type

- Livo's `Feed` carries `upstreamUrl` and `fetchSource` fields (seen in
  `feed-source-provider.ts` usage), i.e. the source kind / generated URL are
  persisted on the feed row.

**Implication for us**: Confirms ADR #5 — `feeds.feed_type` + `provider_input`
are the Rust equivalent (simpler: one type tag + the original input, instead of
Livo's `upstreamUrl`+`fetchSource`).

## 5. Bilibili / YouTube / WeChat specifics (for follow-up sub-tasks)

- **YouTube**: not yet inspected in detail, but YouTube has native RSS
  (`/feeds/videos.xml?channel_id=...`) that `feed-rs` parses — P3c's
  `YoutubeProvider` needs no Livo reference.
- **Bilibili**: RSSHub route `/bilibili/user/dynamic/:uid` (confirmed in
  `getFeedKey`). Livo's `services/bilibili/` + `mapBilibiliVideoCardsToFeed`
  suggest Livo *also* has a self-built path that maps Bilibili API cards to a
  feed — worth a dedicated look when the Bilibili follow-up sub-task starts.
- **WeChat-MP**: backend-proxy rewrite (see §2) — a pure RSSHub route may not
  work reliably; the WeChat follow-up sub-task should decide RSSHub route vs a
  bridge.

## Conclusion

All five ADR decisions hold against Livo's implementation. The provider trait
(ADR #2) is an explicit improvement over Livo's normalize-function approach;
the `opml` crate (ADR #4) replaces Livo's hand-rolled parser; `settings` table
(ADR #3) + `feed_type`/`provider_input` columns (ADR #5) mirror Livo's
`rsshubInstance` setting + `upstreamUrl`/`fetchSource` fields. No ADR changes
needed.
