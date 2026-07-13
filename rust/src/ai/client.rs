//! OpenAI-compatible chat completion client.

use std::time::Duration;

use reqwest::{Client, Method, Url};
use serde::{Deserialize, Serialize};

use crate::api::error::AppError;
use crate::api::types::AiConfig;

const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: String,
    pub content: String,
}

impl Message {
    pub fn system(content: impl Into<String>) -> Self {
        Self {
            role: "system".to_string(),
            content: content.into(),
        }
    }

    pub fn user(content: impl Into<String>) -> Self {
        Self {
            role: "user".to_string(),
            content: content.into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatCompletionRequest {
    pub model: String,
    pub messages: Vec<Message>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_tokens: Option<i32>,
}

#[derive(Debug, Clone, Deserialize)]
struct Choice {
    message: Message,
}

#[derive(Debug, Clone, Deserialize)]
struct ChatCompletionResponse {
    choices: Vec<Choice>,
}

/// Sends a chat completion request to the configured endpoint and returns the
/// content of the first choice. Validates that the endpoint is an `http(s)` URL.
pub async fn chat_completion(
    config: &AiConfig,
    request: ChatCompletionRequest,
) -> Result<String, AppError> {
    let url = validate_endpoint(&config.endpoint)?;

    let client = Client::builder()
        .timeout(REQUEST_TIMEOUT)
        .build()
        .map_err(|e| AppError::Network {
            url: config.endpoint.clone(),
            status: 0,
            message: format!("failed to build http client: {e}"),
        })?;

    let mut builder = client
        .request(Method::POST, url)
        .header("Content-Type", "application/json");
    if !config.api_key.is_empty() {
        builder = builder.bearer_auth(&config.api_key);
    }

    let response = builder
        .json(&request)
        .send()
        .await
        .map_err(|e| AppError::Network {
            url: config.endpoint.clone(),
            status: 0,
            message: e.to_string(),
        })?;

    let status = response.status();
    if !status.is_success() {
        let message = response
            .text()
            .await
            .unwrap_or_else(|_| "unknown error".to_string());
        return Err(AppError::Network {
            url: config.endpoint.clone(),
            status: status.as_u16(),
            message,
        });
    }

    let body = response.text().await.map_err(|e| AppError::Network {
        url: config.endpoint.clone(),
        status: status.as_u16(),
        message: e.to_string(),
    })?;

    let parsed: ChatCompletionResponse = serde_json::from_str(&body).map_err(|_| {
        AppError::invalid_input(format!("LLM response was not valid JSON: {body:.200}"))
    })?;

    parsed
        .choices
        .into_iter()
        .next()
        .map(|c| c.message.content)
        .filter(|c| !c.is_empty())
        .ok_or_else(|| {
            AppError::invalid_input("LLM response contained no choices or empty content")
        })
}

fn validate_endpoint(endpoint: &str) -> Result<Url, AppError> {
    let trimmed = endpoint.trim();
    if trimmed.is_empty() {
        return Err(AppError::invalid_input(
            "AI endpoint is not configured. Add it in Settings → AI.",
        ));
    }
    let url = Url::parse(trimmed)
        .map_err(|e| AppError::invalid_input(format!("AI endpoint is not a valid URL: {e}")))?;
    if url.scheme() != "http" && url.scheme() != "https" {
        return Err(AppError::invalid_input(
            "AI endpoint must use http or https.",
        ));
    }
    Ok(url)
}
