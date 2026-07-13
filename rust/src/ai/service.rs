//! AI service orchestration: load config + entry, check cache, call LLM, persist.

use crate::ai::client::chat_completion;
use crate::ai::config::get_ai_config;
use crate::ai::prompts::{strip_html, summary_request, translation_request};
use crate::api::error::AppError;
use crate::db::connection::with_db;
use crate::db::repositories::entry as entry_repo;

/// Generates a concise summary for `entry_id` in the configured target language.
/// Returns the cached DB value if one exists.
pub async fn summarize_entry(entry_id: String) -> Result<String, AppError> {
    let config = get_ai_config()?;
    if config.api_key.is_empty() {
        return Err(AppError::invalid_input(
            "AI API key is not configured. Add it in Settings → AI.",
        ));
    }

    // Check the DB cache first.
    let cached = with_db(|conn| entry_repo::get_entry_ai_text(conn, &entry_id))?;
    if let Some(summary) = cached.0 {
        return Ok(summary);
    }

    let (title, body) = with_db(|conn| {
        let entry = entry_repo::get_entry_by_id(conn, &entry_id)?;
        let title = entry.title;
        let body = entry.content.or(entry.summary).unwrap_or_default();
        Ok((title, body))
    })?;

    let request = summary_request(
        config.model.clone(),
        &title,
        &strip_html(&body),
        &config.target_language,
    );
    let summary = chat_completion(&config, request).await?;

    with_db(|conn| entry_repo::set_entry_ai_summary(conn, &entry_id, &summary))?;
    Ok(summary)
}

/// Translates `entry_id` into `target_language` (defaults to Simplified Chinese
/// when empty). Returns the cached DB value if one exists.
pub async fn translate_entry(
    entry_id: String,
    target_language: String,
) -> Result<String, AppError> {
    let config = get_ai_config()?;
    if config.api_key.is_empty() {
        return Err(AppError::invalid_input(
            "AI API key is not configured. Add it in Settings → AI.",
        ));
    }

    let target = target_language.trim();
    let target = if target.is_empty() { "zh" } else { target };

    // Check the DB cache first.
    let cached = with_db(|conn| entry_repo::get_entry_ai_text(conn, &entry_id))?;
    if target.to_lowercase().starts_with("zh") {
        if let Some(translation) = cached.1 {
            return Ok(translation);
        }
    }

    let (title, body) = with_db(|conn| {
        let entry = entry_repo::get_entry_by_id(conn, &entry_id)?;
        let title = entry.title;
        let body = entry.content.or(entry.summary).unwrap_or_default();
        Ok((title, body))
    })?;

    let request = translation_request(config.model.clone(), &title, &strip_html(&body), target);
    let translation = chat_completion(&config, request).await?;

    if target.to_lowercase().starts_with("zh") {
        with_db(|conn| entry_repo::set_entry_ai_translation_zh(conn, &entry_id, &translation))?;
    }

    Ok(translation)
}
