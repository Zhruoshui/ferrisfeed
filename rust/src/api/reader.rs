use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use url::Url;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReaderSnapshot {
    pub feeds: Vec<Feed>,
    pub articles: Vec<Article>,
    pub last_updated_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Feed {
    pub id: String,
    pub title: String,
    pub source_url: String,
    pub site_url: String,
    pub description: String,
    pub unread_count: i32,
    pub article_count: i32,
    pub last_synced_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Article {
    pub id: String,
    pub feed_id: String,
    pub title: String,
    pub url: String,
    pub author: String,
    pub summary: String,
    pub content: String,
    pub published_at: Option<String>,
    pub is_read: bool,
    pub is_starred: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArticleListItem {
    pub id: String,
    pub feed_id: String,
    pub feed_title: String,
    pub title: String,
    pub summary: String,
    pub published_at: Option<String>,
    pub is_read: bool,
    pub is_starred: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedDraft {
    pub title: String,
    pub source_url: String,
    pub site_url: String,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArticleDraft {
    pub title: String,
    pub url: String,
    pub author: String,
    pub summary: String,
    pub content: String,
    pub published_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportFeedResult {
    pub snapshot_json: String,
    pub feed: Feed,
    pub inserted_articles: Vec<Article>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReaderError {
    pub code: String,
    pub message: String,
}

impl ReaderError {
    fn invalid_input(message: impl Into<String>) -> Self {
        Self {
            code: "invalid_input".to_owned(),
            message: message.into(),
        }
    }

    fn not_found(message: impl Into<String>) -> Self {
        Self {
            code: "not_found".to_owned(),
            message: message.into(),
        }
    }

    fn parse(message: impl Into<String>) -> Self {
        Self {
            code: "parse_error".to_owned(),
            message: message.into(),
        }
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn empty_reader_snapshot_json() -> String {
    serialize_snapshot(&ReaderSnapshot {
        feeds: Vec::new(),
        articles: Vec::new(),
        last_updated_at: None,
    })
}

#[flutter_rust_bridge::frb(sync)]
pub fn decode_reader_snapshot(
    snapshot_json: String,
) -> Result<ReaderSnapshot, ReaderError> {
    decode_snapshot(&snapshot_json)
}

#[flutter_rust_bridge::frb(sync)]
pub fn list_articles(
    snapshot_json: String,
    feed_id: Option<String>,
    show_starred_only: bool,
) -> Result<Vec<ArticleListItem>, ReaderError> {
    let snapshot = decode_snapshot(&snapshot_json)?;
    let mut items = snapshot
        .articles
        .iter()
        .filter(|article| match &feed_id {
            Some(feed_id) => &article.feed_id == feed_id,
            None => true,
        })
        .filter(|article| !show_starred_only || article.is_starred)
        .map(|article| {
            let feed_title = snapshot
                .feeds
                .iter()
                .find(|feed| feed.id == article.feed_id)
                .map(|feed| feed.title.clone())
                .unwrap_or_else(|| "Unknown Feed".to_owned());
            ArticleListItem {
                id: article.id.clone(),
                feed_id: article.feed_id.clone(),
                feed_title,
                title: article.title.clone(),
                summary: article.summary.clone(),
                published_at: article.published_at.clone(),
                is_read: article.is_read,
                is_starred: article.is_starred,
            }
        })
        .collect::<Vec<_>>();
    items.sort_by(|left, right| compare_optional_dates(&right.published_at, &left.published_at));
    Ok(items)
}

#[flutter_rust_bridge::frb(sync)]
pub fn get_article(
    snapshot_json: String,
    article_id: String,
) -> Result<Article, ReaderError> {
    let snapshot = decode_snapshot(&snapshot_json)?;
    snapshot
        .articles
        .into_iter()
        .find(|article| article.id == article_id)
        .ok_or_else(|| ReaderError::not_found("Article not found"))
}

#[flutter_rust_bridge::frb(sync)]
pub fn add_feed(
    snapshot_json: String,
    draft: FeedDraft,
) -> Result<String, ReaderError> {
    let mut snapshot = decode_snapshot(&snapshot_json)?;
    let normalized_source = normalize_url(&draft.source_url)?;
    let normalized_site = normalize_optional_url(&draft.site_url)?;
    if snapshot
        .feeds
        .iter()
        .any(|feed| feed.source_url == normalized_source)
    {
        return Err(ReaderError::invalid_input("Feed already exists"));
    }
    snapshot.feeds.push(Feed {
        id: Uuid::new_v4().to_string(),
        title: non_empty_or(draft.title, "Untitled Feed"),
        source_url: normalized_source,
        site_url: normalized_site.unwrap_or_default(),
        description: draft.description.trim().to_owned(),
        unread_count: 0,
        article_count: 0,
        last_synced_at: None,
    });
    snapshot.last_updated_at = Some(now_iso_string());
    sort_feeds(&mut snapshot.feeds);
    Ok(serialize_snapshot(&snapshot))
}

#[flutter_rust_bridge::frb(sync)]
pub fn remove_feed(
    snapshot_json: String,
    feed_id: String,
) -> Result<String, ReaderError> {
    let mut snapshot = decode_snapshot(&snapshot_json)?;
    let original_feed_count = snapshot.feeds.len();
    snapshot.feeds.retain(|feed| feed.id != feed_id);
    if snapshot.feeds.len() == original_feed_count {
        return Err(ReaderError::not_found("Feed not found"));
    }
    snapshot.articles.retain(|article| article.feed_id != feed_id);
    recalculate_feed_counts(&mut snapshot);
    snapshot.last_updated_at = Some(now_iso_string());
    Ok(serialize_snapshot(&snapshot))
}

#[flutter_rust_bridge::frb(sync)]
pub fn mark_article_read(
    snapshot_json: String,
    article_id: String,
    is_read: bool,
) -> Result<String, ReaderError> {
    let mut snapshot = decode_snapshot(&snapshot_json)?;
    let article = snapshot
        .articles
        .iter_mut()
        .find(|article| article.id == article_id)
        .ok_or_else(|| ReaderError::not_found("Article not found"))?;
    article.is_read = is_read;
    recalculate_feed_counts(&mut snapshot);
    snapshot.last_updated_at = Some(now_iso_string());
    Ok(serialize_snapshot(&snapshot))
}

#[flutter_rust_bridge::frb(sync)]
pub fn toggle_article_star(
    snapshot_json: String,
    article_id: String,
) -> Result<String, ReaderError> {
    let mut snapshot = decode_snapshot(&snapshot_json)?;
    let article = snapshot
        .articles
        .iter_mut()
        .find(|article| article.id == article_id)
        .ok_or_else(|| ReaderError::not_found("Article not found"))?;
    article.is_starred = !article.is_starred;
    snapshot.last_updated_at = Some(now_iso_string());
    Ok(serialize_snapshot(&snapshot))
}

#[flutter_rust_bridge::frb(sync)]
pub fn clear_all_read_articles(snapshot_json: String) -> Result<String, ReaderError> {
    let mut snapshot = decode_snapshot(&snapshot_json)?;
    snapshot.articles.retain(|article| !article.is_read);
    recalculate_feed_counts(&mut snapshot);
    snapshot.last_updated_at = Some(now_iso_string());
    Ok(serialize_snapshot(&snapshot))
}

#[flutter_rust_bridge::frb]
pub async fn import_feed_from_xml(
    snapshot_json: String,
    feed_url: String,
    xml_content: String,
) -> Result<ImportFeedResult, ReaderError> {
    import_feed_from_xml_sync(snapshot_json, feed_url, xml_content)
}

fn import_feed_from_xml_sync(
    snapshot_json: String,
    feed_url: String,
    xml_content: String,
) -> Result<ImportFeedResult, ReaderError> {
    let mut snapshot = decode_snapshot(&snapshot_json)?;
    let normalized_feed_url = normalize_url(&feed_url)?;
    let parsed_feed = parse_feed_xml(&normalized_feed_url, &xml_content)?;

    let feed_id = if let Some(existing_feed) = snapshot
        .feeds
        .iter_mut()
        .find(|feed| feed.source_url == normalized_feed_url)
    {
        existing_feed.title = parsed_feed.feed.title.clone();
        existing_feed.site_url = parsed_feed.feed.site_url.clone();
        existing_feed.description = parsed_feed.feed.description.clone();
        existing_feed.last_synced_at = Some(now_iso_string());
        existing_feed.id.clone()
    } else {
        let feed_id = Uuid::new_v4().to_string();
        snapshot.feeds.push(Feed {
            id: feed_id.clone(),
            title: parsed_feed.feed.title.clone(),
            source_url: normalized_feed_url.clone(),
            site_url: parsed_feed.feed.site_url.clone(),
            description: parsed_feed.feed.description.clone(),
            unread_count: 0,
            article_count: 0,
            last_synced_at: Some(now_iso_string()),
        });
        feed_id
    };

    let mut inserted_articles = Vec::new();
    for draft in parsed_feed.articles {
        let normalized_url = normalize_url(&draft.url)?;
        if snapshot.articles.iter().any(|article| article.url == normalized_url) {
            continue;
        }
        let article = Article {
            id: Uuid::new_v4().to_string(),
            feed_id: feed_id.clone(),
            title: non_empty_or(draft.title, "Untitled Article"),
            url: normalized_url,
            author: draft.author.trim().to_owned(),
            summary: draft.summary.trim().to_owned(),
            content: draft.content.trim().to_owned(),
            published_at: draft.published_at,
            is_read: false,
            is_starred: false,
        };
        inserted_articles.push(article.clone());
        snapshot.articles.push(article);
    }

    sort_feeds(&mut snapshot.feeds);
    sort_articles(&mut snapshot.articles);
    recalculate_feed_counts(&mut snapshot);
    snapshot.last_updated_at = Some(now_iso_string());

    let feed = snapshot
        .feeds
        .iter()
        .find(|feed| feed.id == feed_id)
        .cloned()
        .ok_or_else(|| ReaderError::not_found("Feed not found after import"))?;

    Ok(ImportFeedResult {
        snapshot_json: serialize_snapshot(&snapshot),
        feed,
        inserted_articles,
    })
}

#[derive(Debug)]
struct ParsedFeedPayload {
    feed: FeedDraft,
    articles: Vec<ArticleDraft>,
}

fn decode_snapshot(snapshot_json: &str) -> Result<ReaderSnapshot, ReaderError> {
    if snapshot_json.trim().is_empty() {
        return Ok(ReaderSnapshot {
            feeds: Vec::new(),
            articles: Vec::new(),
            last_updated_at: None,
        });
    }
    serde_json::from_str(snapshot_json)
        .map(|mut snapshot: ReaderSnapshot| {
            sort_feeds(&mut snapshot.feeds);
            sort_articles(&mut snapshot.articles);
            recalculate_feed_counts(&mut snapshot);
            snapshot
        })
        .map_err(|error| ReaderError::parse(format!("Failed to decode reader snapshot: {error}")))
}

fn serialize_snapshot(snapshot: &ReaderSnapshot) -> String {
    serde_json::to_string(snapshot).unwrap_or_else(|_| "{\"feeds\":[],\"articles\":[],\"last_updated_at\":null}".to_owned())
}

fn parse_feed_xml(feed_url: &str, xml_content: &str) -> Result<ParsedFeedPayload, ReaderError> {
    if xml_content.contains("<rss") || xml_content.contains("<channel") {
        parse_rss(feed_url, xml_content)
    } else if xml_content.contains("<feed") {
        parse_atom(feed_url, xml_content)
    } else {
        Err(ReaderError::parse("Unsupported feed format"))
    }
}

fn parse_rss(feed_url: &str, xml_content: &str) -> Result<ParsedFeedPayload, ReaderError> {
    let title = extract_first_tag(xml_content, "channel", "title")
        .or_else(|| extract_tag(xml_content, "title"))
        .unwrap_or_else(|| feed_url.to_owned());
    let description = extract_first_tag(xml_content, "channel", "description")
        .or_else(|| extract_tag(xml_content, "description"))
        .unwrap_or_default();
    let site_url = extract_first_tag(xml_content, "channel", "link")
        .unwrap_or_else(|| feed_url.to_owned());

    let items = extract_blocks(xml_content, "item")
        .into_iter()
        .map(|block| ArticleDraft {
            title: extract_tag(&block, "title").unwrap_or_else(|| "Untitled Article".to_owned()),
            url: extract_tag(&block, "link").unwrap_or_default(),
            author: extract_tag(&block, "author")
                .or_else(|| extract_tag(&block, "dc:creator"))
                .unwrap_or_default(),
            summary: extract_tag(&block, "description")
                .or_else(|| extract_tag(&block, "content:encoded"))
                .unwrap_or_default(),
            content: extract_tag(&block, "content:encoded")
                .or_else(|| extract_tag(&block, "description"))
                .unwrap_or_default(),
            published_at: extract_tag(&block, "pubDate")
                .and_then(|value| normalize_date_string(&value)),
        })
        .filter(|article| !article.url.trim().is_empty())
        .collect::<Vec<_>>();

    Ok(ParsedFeedPayload {
        feed: FeedDraft {
            title,
            source_url: feed_url.to_owned(),
            site_url,
            description,
        },
        articles: items,
    })
}

fn parse_atom(feed_url: &str, xml_content: &str) -> Result<ParsedFeedPayload, ReaderError> {
    let title = extract_tag(xml_content, "title").unwrap_or_else(|| feed_url.to_owned());
    let subtitle = extract_tag(xml_content, "subtitle").unwrap_or_default();
    let site_url = extract_atom_link(xml_content).unwrap_or_else(|| feed_url.to_owned());

    let entries = extract_blocks(xml_content, "entry")
        .into_iter()
        .map(|block| {
            let summary = extract_tag(&block, "summary").unwrap_or_default();
            let content = extract_tag(&block, "content").unwrap_or_else(|| summary.clone());
            ArticleDraft {
                title: extract_tag(&block, "title").unwrap_or_else(|| "Untitled Article".to_owned()),
                url: extract_atom_link(&block).unwrap_or_default(),
                author: extract_nested_author_name(&block).unwrap_or_default(),
                summary,
                content,
                published_at: extract_tag(&block, "updated")
                    .or_else(|| extract_tag(&block, "published"))
                    .and_then(|value| normalize_date_string(&value)),
            }
        })
        .filter(|article| !article.url.trim().is_empty())
        .collect::<Vec<_>>();

    Ok(ParsedFeedPayload {
        feed: FeedDraft {
            title,
            source_url: feed_url.to_owned(),
            site_url,
            description: subtitle,
        },
        articles: entries,
    })
}

fn recalculate_feed_counts(snapshot: &mut ReaderSnapshot) {
    for feed in &mut snapshot.feeds {
        let mut unread_count = 0;
        let mut article_count = 0;
        for article in &snapshot.articles {
            if article.feed_id == feed.id {
                article_count += 1;
                if !article.is_read {
                    unread_count += 1;
                }
            }
        }
        feed.article_count = article_count;
        feed.unread_count = unread_count;
    }
}

fn sort_feeds(feeds: &mut [Feed]) {
    feeds.sort_by(|left, right| left.title.to_lowercase().cmp(&right.title.to_lowercase()));
}

fn sort_articles(articles: &mut [Article]) {
    articles.sort_by(|left, right| compare_optional_dates(&right.published_at, &left.published_at));
}

fn compare_optional_dates(left: &Option<String>, right: &Option<String>) -> std::cmp::Ordering {
    match (left, right) {
        (Some(left), Some(right)) => left.cmp(right),
        (Some(_), None) => std::cmp::Ordering::Greater,
        (None, Some(_)) => std::cmp::Ordering::Less,
        (None, None) => std::cmp::Ordering::Equal,
    }
}

fn normalize_url(value: &str) -> Result<String, ReaderError> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(ReaderError::invalid_input("URL cannot be empty"));
    }
    Url::parse(trimmed)
        .map(|url| url.to_string())
        .map_err(|error| ReaderError::invalid_input(format!("Invalid URL: {error}")))
}

fn normalize_optional_url(value: &str) -> Result<Option<String>, ReaderError> {
    if value.trim().is_empty() {
        Ok(None)
    } else {
        normalize_url(value).map(Some)
    }
}

fn non_empty_or(value: String, fallback: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        fallback.to_owned()
    } else {
        trimmed.to_owned()
    }
}

fn now_iso_string() -> String {
    Utc::now().to_rfc3339()
}

fn normalize_date_string(value: &str) -> Option<String> {
    DateTime::parse_from_rfc2822(value)
        .or_else(|_| DateTime::parse_from_rfc3339(value))
        .map(|date| date.with_timezone(&Utc).to_rfc3339())
        .ok()
}

fn extract_blocks(input: &str, tag: &str) -> Vec<String> {
    let mut blocks = Vec::new();
    let open = format!("<{tag}");
    let close = format!("</{tag}>");
    let mut cursor = 0;
    while let Some(open_index) = input[cursor..].find(&open) {
        let absolute_open = cursor + open_index;
        let Some(open_end) = input[absolute_open..].find('>') else {
            break;
        };
        let content_start = absolute_open + open_end + 1;
        let Some(close_index) = input[content_start..].find(&close) else {
            break;
        };
        let content_end = content_start + close_index;
        blocks.push(input[content_start..content_end].to_owned());
        cursor = content_end + close.len();
    }
    blocks
}

fn extract_tag(input: &str, tag: &str) -> Option<String> {
    let open = format!("<{tag}");
    let start = input.find(&open)?;
    let start_rest = &input[start..];
    let open_end = start_rest.find('>')?;
    let value_start = start + open_end + 1;
    let close = format!("</{tag}>");
    let value_end = input[value_start..].find(&close)? + value_start;
    Some(clean_xml_text(&input[value_start..value_end]))
}

fn extract_first_tag(input: &str, outer_tag: &str, inner_tag: &str) -> Option<String> {
    extract_blocks(input, outer_tag)
        .into_iter()
        .find_map(|block| extract_tag(&block, inner_tag))
}

fn extract_atom_link(input: &str) -> Option<String> {
    let mut cursor = 0;
    while let Some(index) = input[cursor..].find("<link") {
        let absolute = cursor + index;
        let end = input[absolute..].find('>')? + absolute;
        let tag = &input[absolute..=end];
        let href = extract_attribute(tag, "href");
        let rel = extract_attribute(tag, "rel").unwrap_or_default();
        if href.is_some() && (rel.is_empty() || rel == "alternate") {
            return href.as_deref().map(clean_xml_text);
        }
        cursor = end + 1;
    }
    None
}

fn extract_attribute(input: &str, name: &str) -> Option<String> {
    let needle = format!("{name}=\"");
    let start = input.find(&needle)? + needle.len();
    let end = input[start..].find('"')? + start;
    Some(input[start..end].to_owned())
}

fn extract_nested_author_name(input: &str) -> Option<String> {
    extract_blocks(input, "author")
        .into_iter()
        .find_map(|block| extract_tag(&block, "name").or_else(|| extract_tag(&block, "email")))
}

fn clean_xml_text(value: &str) -> String {
    value
        .replace("<![CDATA[", "")
        .replace("]]>", "")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .trim()
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_RSS: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Example Feed</title>
    <link>https://example.com</link>
    <description>Example stories</description>
    <item>
      <title>First story</title>
      <link>https://example.com/articles/1</link>
      <description>Hello from the feed</description>
      <pubDate>Wed, 17 Jun 2026 10:00:00 GMT</pubDate>
    </item>
    <item>
      <title>Second story</title>
      <link>https://example.com/articles/2</link>
      <description>Second article</description>
      <pubDate>Wed, 17 Jun 2026 11:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>"#;

    #[test]
    fn parse_rss_extracts_feed_and_articles() {
        let parsed = parse_feed_xml("https://example.com/feed.xml", SAMPLE_RSS).unwrap();

        assert_eq!(parsed.feed.title, "Example Feed");
        assert_eq!(parsed.feed.site_url, "https://example.com");
        assert_eq!(parsed.articles.len(), 2);
        assert_eq!(parsed.articles[0].title, "First story");
        assert_eq!(parsed.articles[1].url, "https://example.com/articles/2");
    }

    #[test]
    fn import_feed_deduplicates_articles_by_url() {
        let first_import = import_feed_from_xml_sync(
            empty_reader_snapshot_json(),
            "https://example.com/feed.xml".to_owned(),
            SAMPLE_RSS.to_owned(),
        )
        .unwrap();

        assert_eq!(first_import.inserted_articles.len(), 2);

        let second_import = import_feed_from_xml_sync(
            first_import.snapshot_json,
            "https://example.com/feed.xml".to_owned(),
            SAMPLE_RSS.to_owned(),
        )
        .unwrap();

        assert_eq!(second_import.inserted_articles.len(), 0);
        let snapshot = decode_reader_snapshot(second_import.snapshot_json).unwrap();
        assert_eq!(snapshot.feeds.len(), 1);
        assert_eq!(snapshot.articles.len(), 2);
    }

    #[test]
    fn mark_read_and_clear_read_updates_counts() {
        let import_result = import_feed_from_xml_sync(
            empty_reader_snapshot_json(),
            "https://example.com/feed.xml".to_owned(),
            SAMPLE_RSS.to_owned(),
        )
        .unwrap();
        let article_id = import_result.inserted_articles[0].id.clone();

        let marked_snapshot = mark_article_read(import_result.snapshot_json, article_id, true).unwrap();
        let snapshot = decode_reader_snapshot(marked_snapshot.clone()).unwrap();
        assert_eq!(snapshot.feeds[0].article_count, 2);
        assert_eq!(snapshot.feeds[0].unread_count, 1);

        let cleared_snapshot = clear_all_read_articles(marked_snapshot).unwrap();
        let cleared = decode_reader_snapshot(cleared_snapshot).unwrap();
        assert_eq!(cleared.articles.len(), 1);
        assert_eq!(cleared.feeds[0].article_count, 1);
        assert_eq!(cleared.feeds[0].unread_count, 1);
    }
}
