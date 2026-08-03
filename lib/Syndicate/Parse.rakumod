use v6.d;
use XML;
use Syndicate::RSS;
use Syndicate::RSS::V0_91;
use Syndicate::RSS::V1_0;
use Syndicate::Atom;
use Syndicate::JSONFeed;
use Syndicate::Stats;
use JSON::Fast;
my constant MAX-FEED-SIZE is export = 10 * 1024 * 1024;
my constant RSS_VER_091      = "0.91";

unit module Syndicate::Parse:ver<0.0.1>:auth<zef:sasha>;

enum FeedFormat is export <Atom RSS2 RSS091 RSS1 JSONFeedFmt>;

sub sanitize-raw(Str $input --> Str) {
    my $clean = $input.trim;
    $clean .= subst(/^\xFEFF/, '');
    die "empty input" unless $clean.chars;
    die "input too large ({$clean.chars} chars)" if $clean.chars > MAX-FEED-SIZE;
    if $clean.chars > MAX-FEED-SIZE / 4 {
        my $bytes = $clean.encode.bytes;
        die "input too large ($bytes bytes, max {MAX-FEED-SIZE})" if $bytes > MAX-FEED-SIZE;
    }
    $clean
}

# Shared trim/BOM/size normalization. The recording variant records a Stats
# error and re-dies with the underlying message; the non-recording variant
# returns Nil so probes (e.g. Discovery) can treat invalid input as "not a
# feed" without counting an error.
our sub sanitize-input(Str $input --> Str) is export {
    my $clean = try { sanitize-raw($input) };
    unless $clean.defined {
        Syndicate::Stats.record-error;
        die $!;
    }
    $clean
}

our sub sanitize-input-nonrecording(Str $input --> Str) is export {
    try { sanitize-raw($input) }
}

# Note: feed-format() followed by parse-feed() parses XML twice.
# Use parse-feed-with-format() when both format and feed are needed.
our proto sub feed-format(|) is export {*}

multi sub feed-format(Str $input --> FeedFormat) is export {
    my $clean = sanitize-input($input);

    with try-xml-parse($clean) -> $root {
        return feed-format($root<name>, $root<ver>);
    }

    my $parsed-json = try { from-json($clean) };
    if is-json-feed($parsed-json) {
        return JSONFeedFmt;
    }
    Syndicate::Stats.record-error;
    die $parsed-json.defined
        ?? "feed-format: valid JSON but not a JSON Feed (version must start with '{JSONFEED-VERSION-PREFIX}')"
        !! "feed-format: unable to detect feed format — input is not valid XML or JSON";
}

multi sub feed-format(Str $name, Str $ver) {
    with format-for($name, $ver) -> $fmt {
        return $fmt;
    }
    Syndicate::Stats.record-error;
    die "Unknown feed format: <{$name}>"
}

# Single-parse non-recording probe that also parses the feed, for code
# paths (e.g. Discovery) that must not count a non-feed (e.g. an HTML page)
# as an error. Detects format and builds the feed from one XML/JSON parse,
# returning Nil when the input is not a feed — without recording an error.
# Errors raised while parsing an actual feed (bad entries, etc.) still
# propagate, matching parse-feed().
our sub parse-feed-or-nil(Str $input --> Syndicate::Feed) is export {
    my $clean = sanitize-input-nonrecording($input);
    return Nil unless $clean.defined;
    with try-xml-parse($clean) -> $root-info {
        return Nil unless format-for($root-info<name>, $root-info<ver>).defined;
        return parse-feed($root-info<doc>);
    }
    my $parsed-json = try { from-json($clean) };
    if is-json-feed($parsed-json) {
        return Syndicate::JSONFeed.new-from-hash(%$parsed-json);
    }
    Nil
}

sub format-for(Str $name, Str $ver --> FeedFormat) {
    given $name {
        when 'feed'   { return Atom }
        when 'rss'    { return $ver eq RSS_VER_091 ?? RSS091 !! RSS2 }
        when 'rdf:RDF' | 'RDF' { return RSS1 }
        default       { return Nil }
    }
}

multi sub feed-format(XML::Document $doc --> FeedFormat) is export {
    my $root = $doc.root;
    feed-format($root.name, $root.attribs<version> // "")
}

our proto sub parse-feed(|) is export {*}

multi sub parse-feed(Str $input --> Syndicate::Feed:D) is export {
    my $clean = sanitize-input($input);

    my $looks-like-xml = $clean.starts-with('<');
    if $looks-like-xml {
        with try-xml-parse($clean) -> $root-info {
            return parse-feed($root-info<doc>);
        }
        Syndicate::Stats.record-error;
        die "parse-feed: XML parsing failed — input is not valid XML";
    }

    my $parsed-json = try { from-json($clean) };
    if is-json-feed($parsed-json) {
        my $feed = Syndicate::JSONFeed.new-from-hash(%$parsed-json);
        Syndicate::Stats.record-feed;
        return $feed;
    }
    Syndicate::Stats.record-error;
    die $parsed-json.defined
        ?? "parse-feed: valid JSON but not a JSON Feed (version must start with '{JSONFEED-VERSION-PREFIX}')"
        !! "parse-feed: unable to detect feed format — input is not valid XML or JSON";
}

multi sub parse-feed(XML::Document $doc --> Syndicate::Feed:D) is export {
    my $root = $doc.root;
    my $feed;
    given $root.name {
        when 'feed' { $feed = Syndicate::Atom.new($doc) }
        when 'rss' {
            my $ver = $root.attribs<version> // "";
            $feed = $ver eq '0.91'
                ?? Syndicate::RSS::V0_91.new($doc)
                !! Syndicate::RSS.new($doc);
        }
        when 'rdf:RDF' | 'RDF' {
            $feed = Syndicate::RSS::V1_0.new($doc);
        }
        default {
            Syndicate::Stats.record-error;
            die "Unknown feed format: <{$root.name}>"
        }
    }
    Syndicate::Stats.record-feed;
    $feed
}

our proto sub parse-feed-with-format(|) is export {*}

multi sub parse-feed-with-format(Str $input --> List) is export {
    my $clean = sanitize-input($input);

    with try-xml-parse($clean) -> $root-info {
        my $format = feed-format($root-info<name>, $root-info<ver>);
        my $feed   = parse-feed($root-info<doc>);
        return ($format, $feed);
    }

    my $parsed-json = try { from-json($clean) };
    if is-json-feed($parsed-json) {
        my $feed = Syndicate::JSONFeed.new-from-hash(%$parsed-json);
        Syndicate::Stats.record-feed;
        return (JSONFeedFmt, $feed);
    }
    Syndicate::Stats.record-error;
    die $parsed-json.defined
        ?? "parse-feed-with-format: valid JSON but not a JSON Feed (version must start with '{JSONFEED-VERSION-PREFIX}')"
        !! "parse-feed-with-format: unable to detect feed format — input is not valid XML or JSON";
}

our proto sub parse-file(|) is export {*}

multi sub parse-file(Str $path --> Syndicate::Feed:D) is export {
    my $size = try { $path.IO.s };
    unless $size.defined {
        die "Could not read file '$path': $!";
    }
    die "File too large ($size bytes, max {MAX-FEED-SIZE})" if $size > MAX-FEED-SIZE;
    my $contents = try { slurp($path) };
    without $contents {
        die "Could not read file '$path': $!";
    }
    parse-feed($contents)
}

multi sub parse-file(IO::Path $path --> Syndicate::Feed:D) is export {
    parse-file($path.Str)
}

# True when $parsed is a Hash whose version starts with the JSON Feed prefix.
sub is-json-feed(Any $parsed --> Bool) {
    $parsed ~~ Hash
        && $parsed<version>.defined
        && $parsed<version>.starts-with(JSONFEED-VERSION-PREFIX)
}

sub try-xml-parse(Str $clean) {
    my $stripped = $clean;
    return Nil if $stripped.starts-with('{') || $stripped.starts-with('[');
    root-element($stripped)
}

sub root-element(Str $input) {
    my $doc = try { XML::Document.new($input) };
    return Nil unless $doc;
    my $root = $doc.root;
    my $name = $root.name;
    my $ver = $root.attribs<version> // "";
    return Nil unless $name.chars;
    %(:$name, :$ver, :$doc)
}

=begin pod

=head1 NAME

Syndicate::Parse - Feed format detection and parsing dispatcher

=head1 SYNOPSIS

=begin code :lang<raku>
use Syndicate::Parse;

my $format = feed-format($input);       # Detect format
my $feed   = parse-feed($input);        # Parse any format (from string)
my $feed   = parse-file("feed.xml");    # Parse from file path (Str or IO::Path)

my ($format, $feed) = parse-feed-with-format($input); # Both, one XML parse
=end code

=head1 DESCRIPTION

Provides auto-detection of feed format from raw input and dispatching
to the appropriate parser class.

B<Security note:> The underlying C<XML> module's behavior on entity
expansion is version-dependent. In multi-tenant or untrusted-input
scenarios, consider pre-scanning input or using an external XML parser
with explicit XXE and billion-laughs protections.

=head1 ENUM C<FeedFormat>

=item C<Atom> - Atom 1.0
=item C<RSS2> - RSS 2.0
=item C<RSS091> - RSS 0.91
=item C<RSS1> - RSS 1.0
=item C<JSONFeedFmt> - JSON Feed

=head1 EXPORTED SUBS

=head2 C<feed-format(Str $input --> FeedFormat)>

Detects feed format by inspecting the raw input:
JSON feeds starting with C<{>, XML feeds by root element name and version attribute.

B<Note:> A JSON document is only recognized as a feed when it carries a
C<version> starting with C<https://jsonfeed.org/version/>. Arbitrary JSON
(e.g. a bare object without that field) is rejected as "not a JSON Feed"
rather than silently treated as one. This is intentionally stricter than
C<Syndicate::JSONFeed.new-from-hash>, which defaults a missing version to 1.1.

=head2 C<parse-feed(Str $input)>

Detects format and returns an object of the appropriate class
(C<Syndicate::Atom>, C<Syndicate::RSS>, C<Syndicate::RSS::V0_91>,
C<Syndicate::RSS::V1_0>, or C<Syndicate::JSONFeed>).

=head2 C<parse-feed-with-format(Str $input --> List)>

Detects the format and parses the feed in a single pass, returning a
C<(FeedFormat, Syndicate::Feed)> List. Use this instead of calling
C<feed-format($input)> followed by C<parse-feed($input)> — that
sequence parses the XML twice, once per call. This sub calls the
underlying XML parser only once.

=for code :lang<raku>
my ($format, $feed) = parse-feed-with-format($input);

=head2 C<parse-file(Str $path)> / C<parse-file(IO::Path $path)>

Reads a file from disk and parses it as a feed (auto-detected format).
Throws if the file cannot be read or is not valid feed content.
Assumes UTF-8 encoding. For non-UTF-8 feed files, read the content
manually with the appropriate encoding and pass to C<parse-feed>.

=for code :lang<raku>
my $feed = parse-file("feed.xml");
my $feed = parse-file("feed.xml".IO);

=end pod
