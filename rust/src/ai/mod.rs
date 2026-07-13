//! AI/LLM integration for on-demand article summary and translation.
//!
//! This module is NOT exposed to flutter_rust_bridge directly; the thin
//! `api::ai` layer delegates here. It mirrors the `feed/` module: HTTP client,
//! prompt templates, config parsing, and orchestration live inside this module.

pub mod client;
pub mod config;
pub mod prompts;
pub mod service;

pub use service::{summarize_entry, translate_entry};
