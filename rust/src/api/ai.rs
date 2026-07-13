//! AI summary/translation APIs exposed over flutter_rust_bridge.
//!
//! Thin wrappers around `crate::ai`; all LLM-specific logic lives in that module.

use crate::api::error::AppError;
use crate::api::types::AiConfig;

/// Generates a concise AI summary for `entry_id` in the configured target
/// language. Returns the cached value from the database if one exists.
#[flutter_rust_bridge::frb]
pub async fn summarize_entry(entry_id: String) -> Result<String, AppError> {
    crate::ai::summarize_entry(entry_id).await
}

/// Translates `entry_id` into `target_language`. Returns the cached value from
/// the database if one exists.
#[flutter_rust_bridge::frb]
pub async fn translate_entry(
    entry_id: String,
    target_language: String,
) -> Result<String, AppError> {
    crate::ai::translate_entry(entry_id, target_language).await
}

/// Returns the configured AI provider, with defaults for unset keys.
#[flutter_rust_bridge::frb]
pub fn get_ai_config() -> Result<AiConfig, AppError> {
    crate::ai::config::get_ai_config()
}

/// Persists the AI provider configuration.
#[flutter_rust_bridge::frb]
pub fn set_ai_config(config: AiConfig) -> Result<(), AppError> {
    crate::ai::config::set_ai_config(&config)
}
