//! AI provider configuration loaded from the `settings` key/value table.

use crate::api::error::AppError;
use crate::api::types::AiConfig;
use crate::db::connection::with_db;
use crate::db::repositories::settings as settings_repo;

pub const AI_ENDPOINT_KEY: &str = "ai.endpoint";
pub const AI_MODEL_KEY: &str = "ai.model";
pub const AI_API_KEY_KEY: &str = "ai.api_key";
pub const AI_TARGET_LANGUAGE_KEY: &str = "ai.target_language";

pub const DEFAULT_AI_ENDPOINT: &str = "https://api.openai.com/v1/chat/completions";
pub const DEFAULT_AI_MODEL: &str = "gpt-4o-mini";
pub const DEFAULT_AI_TARGET_LANGUAGE: &str = "zh";

/// Returns the persisted AI config, falling back to sensible defaults for keys
/// that are unset or empty.
pub fn get_ai_config() -> Result<AiConfig, AppError> {
    with_db(|conn| {
        let endpoint = settings_repo::get_setting(conn, AI_ENDPOINT_KEY)?
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_AI_ENDPOINT.to_string());
        let model = settings_repo::get_setting(conn, AI_MODEL_KEY)?
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_AI_MODEL.to_string());
        let api_key = settings_repo::get_setting(conn, AI_API_KEY_KEY)?
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_default();
        let target_language = settings_repo::get_setting(conn, AI_TARGET_LANGUAGE_KEY)?
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_AI_TARGET_LANGUAGE.to_string());
        Ok(AiConfig {
            endpoint,
            model,
            api_key,
            target_language,
        })
    })
}

/// Persists the AI config. Empty strings are stored as `NULL` so that subsequent
/// reads fall back to defaults where applicable.
pub fn set_ai_config(config: &AiConfig) -> Result<(), AppError> {
    with_db(|conn| {
        let endpoint = config.endpoint.trim();
        let model = config.model.trim();
        let api_key = config.api_key.trim();
        let target_language = config.target_language.trim();

        settings_repo::set_setting(
            conn,
            AI_ENDPOINT_KEY,
            if endpoint.is_empty() {
                None
            } else {
                Some(endpoint)
            },
        )?;
        settings_repo::set_setting(
            conn,
            AI_MODEL_KEY,
            if model.is_empty() { None } else { Some(model) },
        )?;
        settings_repo::set_setting(
            conn,
            AI_API_KEY_KEY,
            if api_key.is_empty() {
                None
            } else {
                Some(api_key)
            },
        )?;
        settings_repo::set_setting(
            conn,
            AI_TARGET_LANGUAGE_KEY,
            if target_language.is_empty() {
                None
            } else {
                Some(target_language)
            },
        )?;
        Ok(())
    })
}
