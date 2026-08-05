NAME
====

Syndicate - Syndication feed parser and generator

SYNOPSIS
========

```raku
use Syndicate;

# Parse any feed (auto-detected)
my $feed = parse($xml-or-json);

# Parse explicit formats
my $rss   = parse-rss($xml);
my $atom  = parse-atom($xml);

# Export all format classes
use Syndicate::Builder::Feed;
my $fb = Syndicate::Builder::Feed.new;
$fb.title("My Feed");
$fb.add-entry.title("Article 1");
say $fb.rss-str;
say $fb.atom-str;
```

DESCRIPTION
===========

Syndicate supports parsing and generation of RSS 2.0, RSS 0.91, RSS 1.0, Atom 1.0, and JSON Feed 1.1. Provides a uniform API via [`Syndicate::Feed`](rakudoc:Syndicate::Feed) and [`Syndicate::Item`](rakudoc:Syndicate::Item) roles, a format-agnostic builder, feed discovery, and extension support (Dublin Core, Media RSS, iTunes).

**Security note:** The `XML` module's behavior on entity expansion is version-dependent. In multi-tenant or untrusted-input scenarios, consider pre-scanning input or using an external XML parser with explicit XXE and billion-laughs protections. Feed URLs fetched via [`Syndicate::Discovery`](rakudoc:Syndicate::Discovery) are restricted to http/https schemes.

**Note:** The `parse-rss`, `parse-atom`, `parse-json`, `parse-rss1`, and `parse-rss091` subs each apply BOM stripping, size limits, and input trimming via the same `sanitize-input` routine used by `parse-feed`. Use the format- specific subs when you already know the feed format and want a dedicated return type.

EXPORTED SUBS
=============

`parse(Str $input)`
-------------------

Auto-detect format and parse, returning a `Syndicate::Feed`-compatible object.

`parse-rss(Str $xml)`
---------------------

Parse RSS 2.0 XML, returning `Syndicate::RSS`.

`parse-atom(Str $xml)`
----------------------

Parse Atom 1.0 XML, returning `Syndicate::Atom`.

`parse-json(Str $json)`
-----------------------

Parse JSON Feed, returning `Syndicate::JSONFeed`.

`parse-rss1(Str $xml)`
----------------------

Parse RSS 1.0 XML, returning `Syndicate::RSS::V1_0`.

`parse-rss091(Str $xml)`
------------------------

Parse RSS 0.91 XML, returning `Syndicate::RSS::V0_91`.

`convert(Str $input, Str $to)`
------------------------------

Parse `$input` (auto-detected) and emit it in the format named by `$to`: `rss` (2.0), `rss091`, `rss1`, `atom`, or `json`. Aliases `rss2`, `rss2.0`, `rss0.91`, and `rss1.0` are accepted. An unknown `$to` dies. The conversion goes through [`Syndicate::Builder::Feed`](rakudoc:Syndicate::Builder::Feed)'s `new-from-feed`, so only builder-supported fields are carried over, and emission may die if the target format requires a field the source lacks (e.g. converting an Atom feed with no description to RSS 2.0 dies with `RSS 2.0 feed requires description`).

