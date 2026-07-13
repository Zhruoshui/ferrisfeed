//! Simhash near-duplicate detection (ports `doc/Livo/src/main/database/entry-simhash.ts`).
//!
//! Produces a 64-bit fingerprint per entry from tokenized text (unigrams +
//! bigrams + trigrams), where each token is hashed with SHA-1 and the bits are
//! folded by per-bit majority voting. Two entries are "near duplicates" when
//! the Hamming distance of their fingerprints is <= 9.
//!
//! The fingerprint is computed from `title + summary + content` (HTML stripped,
//! NFKC-normalized, lowercased, truncated to 1200 chars) to stay stable across
//! re-publications that differ mostly in footer boilerplate. Livo computes the
//! fingerprint on the *read* path and caches it by entry id; here it is used on
//! the sync upsert path to skip inserting near-dup entries within a feed.
//!
//! **Not persisted** (parity with Livo) — fingerprints live only in an in-memory
//! LRU-ish cache keyed by entry id, so cross-session dedup is not supported.
//! Persisting a `simhash` column is a future option.

use std::collections::HashMap;
use std::sync::OnceLock;

use parking_lot::Mutex;
use regex::Regex;
use sha1::{Digest, Sha1};
use unicode_normalization::UnicodeNormalization;

const MIN_TOKEN_COUNT: usize = 18;
const HASH_BITS: usize = 64;
const MAX_DISTANCE_FOR_NEAR_DUPLICATE: u32 = 9;
/// Truncate the normalized text before tokenizing so long articles do not
/// generate tens of thousands of tokens (re-publication deltas are usually in
/// the footer, so the prefix is the stable part). Mirrors Livo.
const SIMHASH_TEXT_BUDGET: usize = 1200;
const SIMHASH_CACHE_MAX: usize = 8192;

/// The content needed to fingerprint an entry. `id` is `None` for entries that
/// have not been inserted yet (new parsed drafts); when present, the computed
/// fingerprint is cached under that id keyed by content lengths so repeated
/// syncs of unchanged entries skip the SHA-1 work.
pub(crate) struct SimhashInput<'a> {
    pub id: Option<&'a str>,
    pub title: &'a str,
    pub summary: Option<&'a str>,
    pub content: Option<&'a str>,
}

/// A cached fingerprint plus the content-lengths signature it was computed
/// from. The lengths act as a cheap invalidation key: if the entry's
/// title/summary/content lengths change, the fingerprint is recomputed.
struct CacheEntry {
    lengths_key: String,
    fingerprint: Option<u64>,
}

static SIMHASH_CACHE: OnceLock<Mutex<HashMap<String, CacheEntry>>> = OnceLock::new();

fn cache() -> &'static Mutex<HashMap<String, CacheEntry>> {
    SIMHASH_CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Computes (or returns the cached) 64-bit simhash fingerprint for `input`.
/// Returns `None` when the entry has too few tokens (< 18) to be meaningful —
/// such entries are never treated as near-duplicates.
pub(crate) fn compute(input: &SimhashInput) -> Option<u64> {
    if let Some(id) = input.id {
        let lengths = lengths_key(input);
        let cached = {
            let guard = cache().lock();
            guard
                .get(id)
                .filter(|e| e.lengths_key == lengths)
                .map(|e| e.fingerprint)
        };
        if let Some(fp) = cached {
            return fp;
        }
        let fp = compute_uncached(input);
        let mut guard = cache().lock();
        if guard.len() >= SIMHASH_CACHE_MAX {
            // Evict ~half the entries (the cache is an optimization only;
            // eviction order is arbitrary, matching Livo's "clear half" intent).
            let to_remove: Vec<String> =
                guard.keys().take(SIMHASH_CACHE_MAX / 2).cloned().collect();
            for key in to_remove {
                guard.remove(&key);
            }
        }
        guard.insert(
            id.to_string(),
            CacheEntry {
                lengths_key: lengths,
                fingerprint: fp,
            },
        );
        fp
    } else {
        compute_uncached(input)
    }
}

/// Hamming distance between two 64-bit fingerprints (number of differing bits).
pub(crate) fn hamming_distance(a: u64, b: u64) -> u32 {
    (a ^ b).count_ones()
}

/// True when the two fingerprints are within the near-duplicate threshold
/// (Hamming distance <= 9).
pub(crate) fn is_near_duplicate(a: u64, b: u64) -> bool {
    hamming_distance(a, b) <= MAX_DISTANCE_FOR_NEAR_DUPLICATE
}

fn compute_uncached(input: &SimhashInput) -> Option<u64> {
    let text = [
        input.title,
        input.summary.unwrap_or(""),
        input.content.unwrap_or(""),
    ]
    .join("\n");
    let normalized = normalize(&text);
    // Truncate by characters (Livo slices by UTF-16 code units; for BMP text —
    // the common case — chars and UTF-16 units coincide).
    let normalized: String = normalized.chars().take(SIMHASH_TEXT_BUDGET).collect();
    let tokens = tokenize(&normalized);
    if tokens.len() < MIN_TOKEN_COUNT {
        return None;
    }

    let mut weights = [0i32; HASH_BITS];
    for i in 0..tokens.len() {
        add_feature(format!("1:{}", tokens[i]), 1, &mut weights);
        if i + 1 < tokens.len() {
            add_feature(
                format!("2:{}\0{}", tokens[i], tokens[i + 1]),
                2,
                &mut weights,
            );
        }
        if i + 2 < tokens.len() {
            add_feature(
                format!("3:{}\0{}\0{}", tokens[i], tokens[i + 1], tokens[i + 2]),
                3,
                &mut weights,
            );
        }
    }

    let mut fingerprint = 0u64;
    for (bit, &w) in weights.iter().enumerate() {
        if w > 0 {
            fingerprint |= 1u64 << bit;
        }
    }
    Some(fingerprint)
}

/// Folds one SHA-1-hashed feature into the per-bit weight array.
///
/// Mirrors Livo: the first 8 bytes of the SHA-1 digest are split into a `hi`
/// u32 (bytes 0-3, big-endian) and `lo` u32 (bytes 4-7, big-endian). `lo`
/// drives bits 0-31, `hi` drives bits 32-63. Each bit accumulates `+weight`
/// when set, `-weight` when clear; the final fingerprint sets bit `i` when the
/// accumulated weight is positive (majority vote).
fn add_feature(feature: String, weight: i32, weights: &mut [i32; HASH_BITS]) {
    let mut hasher = Sha1::new();
    hasher.update(feature.as_bytes());
    let digest = hasher.finalize();
    let hi = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]);
    let lo = u32::from_be_bytes([digest[4], digest[5], digest[6], digest[7]]);
    for bit in 0..32u32 {
        weights[bit as usize] += if (lo >> bit) & 1 == 1 {
            weight
        } else {
            -weight
        };
        weights[bit as usize + 32] += if (hi >> bit) & 1 == 1 {
            weight
        } else {
            -weight
        };
    }
}

/// Strips HTML tags, NFKC-normalizes, lowercases, collapses non-token runs to
/// single spaces, and trims. Ports `normalizeForSimHash` + `stripHtml`.
fn normalize(text: &str) -> String {
    let stripped = html_tag_re().replace_all(text, " ");
    let nfkc: String = stripped.nfkc().collect();
    let lower = nfkc.to_lowercase();
    let replaced = non_token_re().replace_all(&lower, " ");
    let collapsed = whitespace_re().replace_all(&replaced, " ");
    collapsed.trim().to_string()
}

/// Tokenizes into single Han characters or maximal runs of letters/numbers.
/// Ports `/[\p{Script=Han}]|[\p{L}\p{N}]+/u`.
fn tokenize(text: &str) -> Vec<&str> {
    token_re().find_iter(text).map(|m| m.as_str()).collect()
}

fn lengths_key(input: &SimhashInput) -> String {
    format!(
        "{}:{}:{}",
        input.title.len(),
        input.summary.map(|s| s.len()).unwrap_or(0),
        input.content.map(|s| s.len()).unwrap_or(0),
    )
}

fn html_tag_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"<[^>]+>").unwrap())
}

fn non_token_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"[^\p{L}\p{N}\p{Han}]+").unwrap())
}

fn whitespace_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"\s+").unwrap())
}

fn token_re() -> &'static Regex {
    static RE: OnceLock<Regex> = OnceLock::new();
    RE.get_or_init(|| Regex::new(r"[\p{Han}]|[\p{L}\p{N}]+").unwrap())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input<'a>(
        id: Option<&'a str>,
        title: &'a str,
        summary: Option<&'a str>,
        content: Option<&'a str>,
    ) -> SimhashInput<'a> {
        SimhashInput {
            id,
            title,
            summary,
            content,
        }
    }

    #[test]
    fn hamming_distance_basics() {
        assert_eq!(hamming_distance(0, 0), 0);
        assert_eq!(hamming_distance(0, 1), 1);
        assert_eq!(hamming_distance(0, u64::MAX), 64);
        assert_eq!(hamming_distance(0b1010, 0b0101), 4);
    }

    #[test]
    fn near_duplicate_threshold() {
        // 9 bits differ -> near-dup.
        let a = 0u64;
        let b = (1u64 << 0)
            | (1u64 << 1)
            | (1u64 << 2)
            | (1u64 << 3)
            | (1u64 << 4)
            | (1u64 << 5)
            | (1u64 << 6)
            | (1u64 << 7)
            | (1u64 << 8);
        assert_eq!(hamming_distance(a, b), 9);
        assert!(is_near_duplicate(a, b));
        // 10 bits differ -> not near-dup.
        let c = b | (1u64 << 9);
        assert_eq!(hamming_distance(a, c), 10);
        assert!(!is_near_duplicate(a, c));
    }

    #[test]
    fn too_few_tokens_returns_none() {
        let fp = compute(&input(None, "hi", None, None));
        assert!(fp.is_none(), "short text should not produce a fingerprint");
    }

    #[test]
    fn identical_text_produces_identical_fingerprint() {
        let title = "Breaking news from the technology sector today";
        let summary = "A detailed summary of the events that unfolded during the conference";
        let content =
            "Full article body with plenty of words to exceed the minimum token count easily";
        let a = compute(&input(None, title, Some(summary), Some(content)));
        let b = compute(&input(None, title, Some(summary), Some(content)));
        assert!(a.is_some());
        assert_eq!(a, b, "identical text must produce identical fingerprints");
    }

    #[test]
    fn near_identical_text_is_near_duplicate() {
        // Two articles that share almost all wording (a re-publication with a
        // small footer/boilerplate delta) should be flagged as near-duplicate.
        let base = "The quick brown fox jumps over the lazy dog near the riverbank \
                    on a sunny afternoon while the children watch in amazement and \
                    the parents take photographs of the unusual scene unfolding";
        let variant = "The quick brown fox jumps over the lazy dog near the riverbank \
                       on a sunny afternoon while the children watch in amazement and \
                       the parents take photographs of the unusual scene developing";
        let a = compute(&input(None, "Fox sighting reported", Some(base), None));
        let b = compute(&input(None, "Fox sighting reported", Some(variant), None));
        let (a, b) = (a.unwrap(), b.unwrap());
        assert!(
            is_near_duplicate(a, b),
            "near-identical text should be near-duplicate (distance = {})",
            hamming_distance(a, b),
        );
    }

    #[test]
    fn unrelated_text_is_not_near_duplicate() {
        let a = compute(&input(
            None,
            "Technology conference highlights",
            Some(
                "Apple announced new products at the developer conference today \
                  including software updates hardware revisions and services",
            ),
            None,
        ))
        .unwrap();
        let b = compute(&input(
            None,
            "Local sports results",
            Some(
                "The hometown team won the championship game last night with a \
                  final score that surprised everyone watching the match",
            ),
            None,
        ))
        .unwrap();
        assert!(
            !is_near_duplicate(a, b),
            "unrelated text should not be near-duplicate (distance = {})",
            hamming_distance(a, b),
        );
    }

    #[test]
    fn html_is_stripped_before_tokenizing() {
        let plain = "Breaking news from the technology sector today with enough \
                     words to exceed the minimum token count for the simhash";
        let html = format!("<p>{plain}</p><div>More text here for token count</div>");
        let a = compute(&input(None, "Title one", Some(plain), None));
        let b = compute(&input(None, "Title one", Some(&html), None));
        // The HTML tags add tokens ("p", "div", "p", "div") that shift the
        // fingerprint, but stripping means the core text is preserved. They
        // should still be close (near-duplicate) because most tokens match.
        let (a, b) = (a.unwrap(), b.unwrap());
        assert!(
            is_near_duplicate(a, b),
            "html-wrapped text should be near-duplicate of plain (distance = {})",
            hamming_distance(a, b),
        );
    }

    #[test]
    fn cache_returns_same_fingerprint_for_unchanged_content() {
        let id = "test-entry-cache-1";
        let title = "Cached entry title with several words";
        let summary = "Summary that provides enough tokens to clear the minimum \
                       threshold for simhash fingerprint computation";
        let first = compute(&input(Some(id), title, Some(summary), None));
        // Mutate then restore to a different entry to ensure the cache is hit.
        let other_id = "test-entry-cache-2";
        let _ = compute(&input(
            Some(other_id),
            "Different",
            Some("Different content"),
            None,
        ));
        let second = compute(&input(Some(id), title, Some(summary), None));
        assert_eq!(first, second);
    }

    #[test]
    fn cache_recomputes_when_content_lengths_change() {
        let id = "test-entry-cache-3";
        let title = "Original title with enough words to pass";
        let summary = "Original summary that has plenty of tokens for the hash \
                       computation to exceed the minimum threshold easily";
        let before = compute(&input(Some(id), title, Some(summary), None));
        // Different lengths -> different cache key -> recompute. The shorter
        // summary still has enough tokens to produce a fingerprint.
        let shorter = "Shorter summary but still long enough to clear the \
                       minimum token count threshold for the simhash";
        let after = compute(&input(Some(id), title, Some(shorter), None));
        assert!(before.is_some(), "before should produce a fingerprint");
        assert!(after.is_some(), "after should produce a fingerprint");
        assert_ne!(before, after, "changed content lengths should recompute");
    }

    #[test]
    fn cjk_text_is_tokenized_into_single_han_characters() {
        // CJK text: each Han character is a token, runs of letters/numbers are
        // tokens. Ensure CJK content produces a fingerprint (not None).
        let title = "科技新闻";
        let content = "今天的新闻报道了一项重要的技术突破这项突破可能会改变整个行业\
                       的发展方向许多专家对此表示关注并发表了各自的看法和意见";
        let fp = compute(&input(None, title, None, Some(content)));
        assert!(fp.is_some(), "CJK content should produce a fingerprint");
    }
}
