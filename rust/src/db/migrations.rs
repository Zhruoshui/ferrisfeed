//! SQLite schema migrations for the reader persistence layer.
//!
//! Ports the MVP subset of Livo's `doc/Livo/src/main/database/sqlite-schema.ts`:
//! only the `feeds`, `entries`, and `categories` tables (+ their indexes) are
//! created here. `fever_*`, `ai_*`, `sync_changes`, and `entry_ai_*` tables are
//! out of scope for P0b.
//!
//! Migrations are tracked by SQLite's `PRAGMA user_version` (an integer) via
//! `rusqlite_migration` — there is no `schema_migrations` table. A single `v1`
//! migration holds the full MVP schema since there are no existing databases to
//! upgrade. Each statement uses `IF NOT EXISTS` so the migration is idempotent.

use rusqlite::Connection;
use rusqlite_migration::{M, Migrations};

use crate::api::AppError;

/// The v1 MVP schema: feeds, entries, categories, and indexes.
const V1_INIT: &str = r#"
CREATE TABLE IF NOT EXISTS feeds (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    source_url TEXT NOT NULL,
    site_url TEXT,
    description TEXT,
    unread_count INTEGER NOT NULL DEFAULT 0,
    article_count INTEGER NOT NULL DEFAULT 0,
    last_synced_at INTEGER,
    article_view_mode TEXT NOT NULL DEFAULT 'global',
    last_error TEXT,
    error_count INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS feeds_source_url_idx ON feeds (source_url);

CREATE TABLE IF NOT EXISTS entries (
    id TEXT PRIMARY KEY,
    feed_id TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    url TEXT NOT NULL DEFAULT '',
    author TEXT,
    summary TEXT,
    content TEXT,
    published_at INTEGER NOT NULL,
    is_read INTEGER NOT NULL DEFAULT 0,
    is_starred INTEGER NOT NULL DEFAULT 0,
    guid TEXT,
    media TEXT,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (feed_id) REFERENCES feeds(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS entries_feed_published_idx
    ON entries (feed_id, published_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS entries_read_published_idx
    ON entries (is_read, published_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS entries_starred_published_idx
    ON entries (is_starred, published_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS entries_published_idx
    ON entries (published_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS entries_url_idx
    ON entries (feed_id, url);
CREATE INDEX IF NOT EXISTS entries_guid_idx
    ON entries (guid);

CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL
);
"#;

/// Runs all pending migrations against `conn`, bringing it to the latest
/// schema version. Safe to call on a fresh database and on an already-current
/// one (idempotent).
pub fn run(conn: &mut Connection) -> Result<(), AppError> {
    let migrations = Migrations::new(vec![M::up(V1_INIT)]);
    migrations
        .to_latest(conn)
        .map_err(|e| AppError::database(format!("migration failed: {e}")))?;
    Ok(())
}
