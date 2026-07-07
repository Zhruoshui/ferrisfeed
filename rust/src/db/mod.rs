//! Persistence layer: SQLite connection, schema migrations, and repositories.
//!
//! This module is NOT exposed to flutter_rust_bridge (only `crate::api` is).
//! The API layer borrows the shared connection via [`connection::with_db`] and
//! delegates to the repository functions in [`repositories`].

pub mod connection;
pub mod migrations;
pub mod repositories;
