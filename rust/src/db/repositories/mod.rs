//! Repository functions for the reader persistence layer.
//!
//! Each function takes a `&rusqlite::Connection` (borrowed from
//! [`crate::db::connection::with_db`]) and performs a single CRUD operation,
//! mapping `rusqlite::Error` into [`AppError`] via the `From` impl in
//! `connection.rs`. Row mappers port `doc/Livo/src/main/database/row-mappers.ts`
//! into `query_map` closures.

pub mod category;
pub mod entry;
pub mod feed;
pub mod settings;

#[cfg(test)]
mod tests;
