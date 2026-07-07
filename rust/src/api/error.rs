//! Project-wide error type for the flutter_rust_bridge API boundary.
//!
//! Replaces the legacy `ReaderError` struct (still in `reader.rs` until P1a
//! removes it).
//! Every FRB-facing function that can fail returns `Result<T, AppError>`.
//! The `anyhow` crate may be used internally in the service layer, but errors
//! must be converted to `AppError` before crossing the FRB boundary so that
//! Dart receives a typed, exhaustively-matchable enum.

use std::fmt;

/// Typed error enum bridged to Dart as a throwable `FrbException`.
///
/// Dart callers can `switch` over the variants exhaustively, unlike the old
/// `ReaderError { code, message }` struct which required string-matching.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub enum AppError {
    /// A resource (feed, entry, category, ...) was not found.
    NotFound { resource: String, id: String },
    /// User-supplied input was invalid (empty URL, duplicate subscription, ...).
    InvalidInput(String),
    /// A network request failed.
    Network { url: String, status: u16, message: String },
    /// A feed could not be parsed (unsupported format, malformed XML, ...).
    FeedParse { url: String, message: String },
    /// A database operation failed.
    Database(String),
    /// An I/O operation failed.
    Io(String),
    /// Authentication is required or has expired.
    Unauthorized,
    /// A write conflicts with existing state (duplicate insert, ...).
    Conflict(String),
}

/// Rust-side convenience constructors. `pub(crate)` so they are not exposed to
/// Dart; unused in P0a, consumed by the service/api layers from P0b on.
#[allow(dead_code)]
impl AppError {
    pub(crate) fn not_found(resource: impl Into<String>, id: impl Into<String>) -> Self {
        Self::NotFound {
            resource: resource.into(),
            id: id.into(),
        }
    }

    pub(crate) fn invalid_input(message: impl Into<String>) -> Self {
        Self::InvalidInput(message.into())
    }

    pub(crate) fn database(message: impl Into<String>) -> Self {
        Self::Database(message.into())
    }
}

impl fmt::Display for AppError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AppError::NotFound { resource, id } => {
                write!(f, "{resource} not found: {id}")
            }
            AppError::InvalidInput(msg) => write!(f, "invalid input: {msg}"),
            AppError::Network { url, status, message } => {
                write!(f, "network error ({status}) for {url}: {message}")
            }
            AppError::FeedParse { url, message } => {
                write!(f, "feed parse error for {url}: {message}")
            }
            AppError::Database(msg) => write!(f, "database error: {msg}"),
            AppError::Io(msg) => write!(f, "io error: {msg}"),
            AppError::Unauthorized => write!(f, "unauthorized"),
            AppError::Conflict(msg) => write!(f, "conflict: {msg}"),
        }
    }
}

impl std::error::Error for AppError {}
