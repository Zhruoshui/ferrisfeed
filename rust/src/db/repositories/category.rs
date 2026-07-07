//! Category repository: CRUD for the `categories` table.
//!
//! Uses the already-FRB-exposed `crate::api::types::Category` DTO (no name
//! clash — `reader.rs` has no `Category`).

use rusqlite::{params, Connection, Row};

use crate::api::types::Category;
use crate::api::AppError;

pub fn list_categories(conn: &Connection) -> Result<Vec<Category>, AppError> {
    let mut stmt = conn.prepare("SELECT * FROM categories ORDER BY title COLLATE NOCASE")?;
    let rows = stmt.query_map([], category_from_row)?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

/// Inserts or replaces a category by `id`.
pub fn upsert_category(conn: &Connection, category: &Category) -> Result<(), AppError> {
    conn.execute(
        "INSERT INTO categories (id, title) VALUES (?1, ?2)
         ON CONFLICT(id) DO UPDATE SET title = excluded.title",
        params![category.id, category.title],
    )?;
    Ok(())
}

pub fn delete_category(conn: &Connection, id: &str) -> Result<(), AppError> {
    conn.execute("DELETE FROM categories WHERE id = ?1", params![id])?;
    Ok(())
}

fn category_from_row(row: &Row) -> Result<Category, rusqlite::Error> {
    Ok(Category {
        id: row.get("id")?,
        title: row.get("title")?,
    })
}
