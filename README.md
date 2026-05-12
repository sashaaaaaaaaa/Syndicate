# Syndicate

Syndication feed parser and generator supporting **RSS 2.0**, **RSS
0.91**, **RSS 1.0**, **Atom 1.0**, and **JSON Feed 1.1**.

## Dependencies

- `XML` — XML parsing and generation (RSS, Atom)
- `JSON::Fast` — JSON parsing and generation
- `DateTime::Grammar` — W3C/ISO 8601 date parsing
- `DateTime::Format` — RFC 2822 date formatting
- `HTTP::Tiny` — Feed fetching via HTTP/HTTPS
- `IO::Socket::SSL` — HTTPS support (required by HTTP::Tiny)
- `URI` — URL resolution

## Installation

```bash
zef install Syndicate
```

### Installing from source

To install from a local folder:

```bash
cd /path/to/Syndicate
zef install .
```

Requires Raku 6.d or later.

## Supported Formats

| Format       | Parse | Generate | Class                          |
|--------------|-------|----------|--------------------------------|
| RSS 2.0      | ✓     | ✓        | `Syndicate::RSS`               |
| RSS 0.91     | ✓     | ✓        | `Syndicate::RSS::V0_91`        |
| RSS 1.0      | ✓     | ✓        | `Syndicate::RSS::V1_0`         |
| Atom 1.0     | ✓     | ✓        | `Syndicate::Atom`              |
| JSON Feed    | ✓     | ✓        | `Syndicate::JSONFeed`          |

## Quick Start

```raku
use Syndicate;

# --- Parse any feed format (auto-detected) ---
my $feed = parse($xml-or-json-string);
say $feed.title;
say $feed.items[0].title;

# --- Build a feed programmatically ---
use Syndicate::Builder::Feed;

my $fb = Syndicate::Builder::Feed.new;
$fb.title("My Podcast");
$fb.link("https://example.com");
$fb.description("A great podcast");
$fb.language("en");
$fb.generator("Syndicate");

my $entry = $fb.add-entry;
$entry.title("Episode 1");
$entry.link("https://example.com/ep1");
$entry.summary("First episode");
$entry.id("urn:uuid:abc-123");
$entry.updated(DateTime.now);

# Generate any format from the same builder
say $fb.rss-str;     # RSS 2.0 XML
say $fb.atom-str;    # Atom 1.0 XML
say $fb.rss091-str;  # RSS 0.91 XML
say $fb.rss1-str;    # RSS 1.0 XML
say $fb.json-str;    # JSON Feed
```

## Parsing Feeds

### Auto-detect format

```raku
use Syndicate;
use Syndicate::Parse;

my $feed = parse-feed($xml-or-json-string);
# or
my $feed = parse($xml-or-json-string);  # exported by Syndicate
```

The parser detects the format automatically:
- `{` → JSON Feed
- `<feed` → Atom 1.0
- `<rss version="0.91"` → RSS 0.91
- `<rss` → RSS 2.0
- `<rdf:RDF` → RSS 1.0

### Explicit format parsing

```raku
my $rss   = Syndicate::RSS.new($xml-string);
my $atom  = Syndicate::Atom.new($xml-string);
my $rss091 = Syndicate::RSS::V0_91.new($xml-string);
my $rss1  = Syndicate::RSS::V1_0.new($xml-string);
my $json  = Syndicate::JSONFeed.new($json-string);
```

Convenience subs are also exported by `Syndicate`:

```raku
my $rss  = parse-rss($xml-string);
my $atom = parse-atom($xml-string);
```

## Building Feeds

### Using the Builder API (format-agnostic)

The builder lets you construct a feed once and output it in any format:

```raku
use Syndicate::Builder::Feed;

my $fb = Syndicate::Builder::Feed.new;
$fb.title("My Feed");
$fb.link("https://example.com");
$fb.description("A test feed");
$fb.id("https://example.com/feed");
$fb.language("en");
$fb.rights("© 2026 Me");
$fb.generator("MyApp");
$fb.icon("https://example.com/icon.png");
$fb.logo("https://example.com/logo.png");
$fb.updated(DateTime.new("2026-06-15T12:00:00Z"));

# Author (stored as name, email, uri)
$fb.author(:name("Jane Doe"), :email("jane@example.com"));

# Categories (multiple allowed)
$fb.category("Tech");
$fb.category("News");

# Add entries
my $e = $fb.add-entry;
$e.title("Article 1");
$e.link("https://example.com/1");
$e.summary("First article");
$e.id("urn:uuid:1111-1111");
$e.updated(DateTime.new("2026-06-15T10:00:00Z"));
$e.published(DateTime.new("2026-06-14T08:00:00Z"));
$e.author(:name("Jane"), :email("jane@example.com"));
$e.category("Raku");
$e.content("<p>Hello <em>world</em></p>", :type("xhtml"));
$e.rights("© Entry");

# Output in any format
say $fb.rss-str;     # RSS 2.0
say $fb.atom-str;    # Atom 1.0
say $fb.rss091-str;  # RSS 0.91
say $fb.rss1-str;    # RSS 1.0
say $fb.json-str;    # JSON Feed

# Or get the feed object directly
my $feed = $fb.atom-feed;
say $feed.updated;
```

### Direct construction (format-specific)

You can also construct feed objects directly with named arguments:

```raku
# RSS 2.0
my $rss = Syndicate::RSS.new(
    :title("My RSS Feed"),
    :link("https://example.com"),
    :description("RSS description"),
    :language("en"),
    :generator("MyApp"),
    :copyright("© 2026"),
    :items([
        Syndicate::RSS::Item.new(
            :title("Item 1"),
            :link("https://example.com/1"),
            :summary("Item description"),
            :author("author@example.com"),
            :updated(DateTime.new("2026-06-15T10:00:00Z")),
            :guid("https://example.com/1"),
        ),
    ]),
);

# Atom 1.0
my $atom = Syndicate::Atom.new(
    :title("My Atom Feed"),
    :id("https://example.com/atom"),
    :link("https://example.com"),
    :description("Atom subtitle"),
    :updated(DateTime.now),
    :rights("© 2026"),
    :generator("MyApp"),
    :items([
        Syndicate::Atom::Item.new(
            :title("Entry 1"),
            :id("https://example.com/1"),
            :link("https://example.com/1"),
            :summary("Entry summary"),
            :content("<p>Hello world</p>"),
            :content-type("xhtml"),
            :updated(DateTime.new("2026-06-15T10:00:00Z")),
            :published(DateTime.new("2026-06-14T08:00:00Z")),
        ),
    ]),
);

# JSON Feed
my $json = Syndicate::JSONFeed.new(
    :title("My JSON Feed"),
    :link("https://example.com"),
    :description("JSON Feed description"),
    :feed_url("https://example.com/feed.json"),
    :language("en"),
    :items([
        Syndicate::JSONFeed::Item.new(
            :title("Post 1"),
            :id("https://example.com/1"),
            :link("https://example.com/1"),
            :summary("Post summary"),
            :content_html("<p>Hello world</p>"),
        ),
    ]),
);
```

### iTunes Podcast Extensions

The builder supports iTunes podcast fields for RSS 2.0:

```raku
$fb.itunes-author("John Doe");
$fb.itunes-summary("A great podcast about Raku");

# Per-item
$e.itunes-author("John Doe");
$e.itunes-summary("Episode summary");
$e.itunes-duration("30:00");
```

## Generating Output

Every feed and item can be stringified to its native format:

```raku
# RSS / Atom → XML string
say ~$rss-feed;      # XML output via .Str
say $rss-feed.Str;   # same
say $rss-feed.XML;   # XML::Element object

# JSON Feed → JSON string
say $json-feed.Str;       # JSON output
say $json-feed.to-json;   # same
say $json-feed.to-hash;   # Perl Hash structure
```

## Feed Discovery

Fetch and auto-detect feeds from URLs:

```raku
use Syndicate::Discovery;

my $disc = Syndicate::Discovery.new;

# Fetch a known feed URL
my $feed = $disc.fetch("https://example.com/feed.xml");

# Discover feed from a webpage (finds <link> tags)
my $feed = $disc.discover("https://example.com");

# Customize HTTP options
my $feed = $disc.fetch("https://example.com/feed.xml",
    :max-redirects(10), :timeout(15));

# Find feed URLs without fetching
my @urls = $disc.find-feeds($html-string, "https://example.com");
```

## Extensions

Extensions are automatically applied during parsing and generation via the `Syndicate::Extensions` registry.

### Dublin Core

Adds `dc:creator`, `dc:date`, `dc:subject` elements to RSS items.

```raku
use Syndicate::Extension::DublinCore;
# Automatically registered — parses and generates dc:* elements
```

### Media RSS

Adds media content and thumbnails to RSS items.

```raku
use Syndicate::Extension::MediaRSS;

# Access parsed media data
.say for $rss-item.media-contents;   # Array of Hashes (url, type, medium, ...)
.say for $rss-item.media-thumbnails; # Array of Hashes (url, width, height)
say $rss-item.media-title;
say $rss-item.media-description;
```

### iTunes Podcast

Adds iTunes podcast elements to RSS feeds and items.

```raku
use Syndicate::Extension::ITunes;

say $rss-feed.itunes-author;
say $rss-feed.itunes-summary;
say $rss-item.itunes-author;
say $rss-item.itunes-summary;
say $rss-item.itunes-duration;
```

## Common API

All feed types do the `Syndicate::Feed` role. All item types do the `Syndicate::Item` role. This provides a uniform interface:

### Feed Role Attributes

| Attribute     | Type       | RSS 2.0 | RSS 0.91 | RSS 1.0 | Atom | JSON Feed |
|---------------|------------|:-------:|:--------:|:-------:|:----:|:---------:|
| `.title`      | `Str`      | ✓       | ✓        | ✓       | ✓    | ✓         |
| `.link`       | `Str`      | ✓       | ✓        | ✓       | ✓    | ✓         |
| `.description`| `Str`      | ✓       | ✓        | ✓       | ✓    | ✓         |
| `.generator`  | `Str`      | ✓       | ✓        | ✓       | ✓    | ✓         |
| `.language`   | `Str`      | ✓       | ✓        | ✓       | ✓    | ✓         |
| `.items`      | `@`        | ✓       | ✓        | ✓       | ✓    | ✓         |

### Item Role Attributes

| Attribute   | Type       | RSS 2.0 | RSS 0.91 | RSS 1.0 | Atom | JSON Feed |
|-------------|------------|:-------:|:--------:|:-------:|:----:|:---------:|
| `.title`    | `Str`      | ✓       | ✓        | ✓       | ✓    | ✓         |
| `.link`     | `Str`      | ✓       | ✓        | ✓       | ✓    | ✓         |
| `.summary`  | `Str`      | ✓       | ✓        | ✓       | ✓    | ✓         |
| `.author`   | `Str`      | ✓       |          | ✓       | ✓    | ✓         |
| `.updated`  | `DateTime` | ✓       |          | ✓       | ✓    |           |
| `.id`       | `Str`      | ✓       | ✓        | ✓       | ✓    | ✓         |
| `.content`  | `Str`      | ✓       | ✓        | ✓       | ✓    | ✓         |

### Format-Specific Attributes

Each format also exposes its own attributes:

**RSS 2.0 Feed:** `copyright`, `managingEditor`, `webMaster`, `pubDate`, `lastBuildDate`, `category`, `docs`, `ttl`, `image`, `itunes-author`, `itunes-summary`

**RSS 2.0 Item:** `guid`, `guid-is-permalink`, `category`, `comments`, `enclosure`, `source`, `media-contents`, `media-thumbnails`, `media-title`, `media-description`, `itunes-author`, `itunes-summary`, `itunes-duration`

**RSS 0.91 Feed:** `copyright`, `managingEditor`, `webMaster`, `rating`, `docs`, `pubDate`, `lastBuildDate`, `image`, `textInput`, `skipHours`, `skipDays`

**RSS 1.0 Feed:** `about`, `image` (hash with url/title/link/about)

**RSS 1.0 Item:** `about`, `dc-subjects`

**Atom Feed:** `id`, `subtitle`, `author`, `author-detail`, `categories`, `updated`, `rights`, `icon`, `logo`, `contributors`, `link-self`, `link-alternate`

**Atom Item:** `author-detail`, `categories`, `published`, `content-type`, `rights`, `source-feed`, `contributors`

**JSON Feed:** `version`, `feed_url`, `user_comment`, `next_url`, `icon`, `favicon`, `author`, `expired`

**JSON Feed Item:** `external_url`, `content_html`, `content_text`, `image`, `banner_image`, `date_published`, `date_modified`, `authors`, `tags`

## Statistics

```raku
use Syndicate::Stats;

say "Feeds parsed: {Syndicate::Stats.feeds-parsed}";
say "Items parsed: {Syndicate::Stats.items-parsed}";

Syndicate::Stats.record-feed;

Syndicate::Stats.record-item;
```

# AUTHOR

Sasha Abbott <sashaa@disroot.org>

# LICENSE

This library is free software; you can redistribute it and/or modify it under CC0.
