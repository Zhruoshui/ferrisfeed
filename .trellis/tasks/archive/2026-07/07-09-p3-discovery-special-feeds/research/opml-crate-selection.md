# OPML crate selection (Rust)

Research for P3a (OPML import/export). Decides whether to use an existing Rust
crate or hand-roll OPML 2.0 XML.

## Candidates (crates.io, queried 2026-07-09)

| Crate | Version | Downloads | Notes |
|---|---|---|---|
| **`opml`** | 1.1.6 | 104,804 (10,390 recent) | "OPML library for Rust." Mainstream choice. Repo: `git.bauke.xyz/Holllo/opml`. Last updated 2024-01-21. |
| `serde-opml` | 0.1.1 | 1,444 | serde-style OPML. Low adoption. |
| `opml-protocol` | 0.1.1 | 36 | New, near-zero adoption. |
| `opml_cli` | 1.1.6 | 10,095 | CLI frontend for the `opml` crate (confirms `opml` is the lib). |

## Recommendation

**Use the `opml` crate** (v1.1.6) for both parsing and serializing OPML 2.0,
rather than hand-rolling XML.

Rationale:
- High adoption (100k+ downloads) and a dedicated CLI consumer -> stable API.
- Handles OPML 2.0 spec compliance (the `<head>`, `<body>`, nested `<outline>`
  tree, `xmlUrl`/`htmlUrl`/`title`/`type` attributes) for us; hand-rolling is
  fiddly and error-prone (escaping, nesting, attribute ordering).
- `feed-rs` (already a dependency) does NOT handle OPML, so no existing dep
  covers this.

## Open items for the P3a child task (not blocking the parent decision)

- Confirm `opml` crate's API surface (`OPML::from_str` / `to_string`? struct
  names for `Outline`) and that it is pure-Rust (no C deps - matches the
  bundled-SQLite, no-system-deps philosophy from P0b).
- Confirm MSRV compatibility with the project's Rust toolchain.
- Map OPML `<outline xmlUrl=...>` -> `subscribe_feed(xmlUrl)` for import, and
  `feeds` table -> OPML `<outline>` tree for export (folder/category ->
  nested outlines). Livo's OPML import/export logic (TS) is the reference for
  field mapping + merge semantics - see the Livo research note once the
  subagent reports.

## Alternatives considered

- **Hand-roll with `quick-xml`**: more control, but re-implements spec
  compliance. Only worth it if `opml` proves incompatible; revisit at P3a.
- **`serde-opml`**: serde-derive ergonomics, but 14x lower adoption and less
  battle-tested. Prefer `opml` unless its API is awkward for our DTOs.
