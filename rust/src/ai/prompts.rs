//! Prompt builders for summary and translation.

use crate::ai::client::{ChatCompletionRequest, Message};

const SUMMARY_TEMPERATURE: f32 = 0.3;
const SUMMARY_MAX_TOKENS: i32 = 512;
const TRANSLATION_TEMPERATURE: f32 = 0.3;
const TRANSLATION_MAX_TOKENS: i32 = 2048;

/// Strips HTML tags and normalizes whitespace to keep prompts short.
pub fn strip_html(html: &str) -> String {
    let text = html
        .replace(['\r'], "")
        .replace("<br>", "\n")
        .replace("<br/>", "\n")
        .replace("<br />", "\n")
        .replace("</p>", "\n\n")
        .replace("</div>", "\n\n");

    // Drop remaining tags.
    let mut out = String::with_capacity(text.len());
    let mut in_tag = false;
    for ch in text.chars() {
        match ch {
            '<' => in_tag = true,
            '>' if in_tag => in_tag = false,
            _ if !in_tag => out.push(ch),
            _ => {}
        }
    }

    collapse_newlines(&out.replace("\u{00a0}", " ").replace("\u{200b}", ""))
        .trim()
        .to_string()
}

/// Builds a summary request in the requested language.
pub fn summary_request(
    model: String,
    title: &str,
    body: &str,
    lang: &str,
) -> ChatCompletionRequest {
    let lang_label = language_label(lang);
    let prompt = format!(
        "请用{lang_label}为下面的文章生成一段简短摘要（不超过 3 句话）。只输出摘要内容，不要解释。\n\n\
         标题：{title}\n\n\
         正文：{body}"
    );
    ChatCompletionRequest {
        model,
        messages: vec![
            Message::system("You are a concise article summarizer."),
            Message::user(prompt),
        ],
        temperature: Some(SUMMARY_TEMPERATURE),
        max_tokens: Some(SUMMARY_MAX_TOKENS),
    }
}

/// Builds a translation request into the target language.
pub fn translation_request(
    model: String,
    title: &str,
    body: &str,
    target: &str,
) -> ChatCompletionRequest {
    let lang_label = language_label(target);
    let prompt = format!(
        "请将下面的文章翻译成{lang_label}。保留原文的段落结构，只输出译文，不要解释。\n\n\
         标题：{title}\n\n\
         正文：{body}"
    );
    ChatCompletionRequest {
        model,
        messages: vec![
            Message::system("You are a precise translator."),
            Message::user(prompt),
        ],
        temperature: Some(TRANSLATION_TEMPERATURE),
        max_tokens: Some(TRANSLATION_MAX_TOKENS),
    }
}

/// Collapses three or more consecutive newlines into two newlines.
fn collapse_newlines(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut newline_count = 0usize;
    for ch in text.chars() {
        if ch == '\n' {
            newline_count += 1;
            if newline_count <= 2 {
                out.push(ch);
            }
        } else {
            newline_count = 0;
            out.push(ch);
        }
    }
    out
}

fn language_label(code: &str) -> &str {
    match code.to_lowercase().as_str() {
        "zh" | "zh-cn" | "zh-hans" | "zh-hans-cn" => "简体中文",
        "en" | "eng" => "English",
        "ja" | "jpn" => "日本語",
        "ko" | "kor" => "한국어",
        "fr" | "fra" => "Français",
        "de" | "deu" => "Deutsch",
        "es" | "spa" => "Español",
        "ru" | "rus" => "Русский",
        _ => code,
    }
}
