use v6.d;
use XML;
use Syndicate::RSS;
use Syndicate::RSS::V0_91;
use Syndicate::RSS::V1_0;
use Syndicate::Atom;
use Syndicate::JSONFeed;
use Syndicate::Stats;
use JSON::Fast;

my constant MAX-FEED-SIZE    = 10 * 1024 * 1024;
my constant RSS_VER_091      = "0.91";

unit module Syndicate::Parse:ver<0.0.1>:auth<zef:sasha>;

enum FeedFormat is export <Atom RSS2 RSS091 RSS1 JSONFeedFmt>;

# Note: feed-format() followed by parse-feed() parses XML twice.
# Use parse-feed-with-format() when both format and feed are needed.
multi sub feed-format(Str $input --> FeedFormat) is export {
    my $clean = $input.trim;
    $clean .= subst(/^\xFEFF/, '');
    die "feed-format: empty input" unless $clean.chars;

    with try-xml-parse($clean) -> $root {
        return feed-format($root<name>, $root<ver>);
    }

    with try-parse-json($clean) {
        return JSONFeedFmt;
    }
    Syndicate::Stats.record-error;
    die "feed-format: unable to detect feed format — input is not valid XML or JSON";
}

multi sub feed-format(Str $name, Str $ver) {
    given $name {
        when 'feed'   { return Atom }
        when 'rss'    { return $ver eq RSS_VER_091 ?? RSS091 !! RSS2 }
        when 'rdf:RDF' | 'RDF' { return RSS1 }
        default { die "Unknown feed format: <$_>" }
    }
}

multi sub feed-format(XML::Document $doc --> FeedFormat) is export {
    my $root = $doc.root;
    feed-format($root.name, $root.attribs<version> // "")
}

multi sub parse-feed(Str $input --> Syndicate::Feed:D) is export {
    my $clean = $input.trim;
    $clean .= subst(/^\xFEFF/, '');  # strip BOM for both XML and JSON paths
    die "parse-feed: empty input" unless $clean.chars;
    my $bytes = $clean.encode.bytes;
    die "parse-feed: input too large ($bytes bytes, max {MAX-FEED-SIZE})"
        if $bytes > MAX-FEED-SIZE;

    my $looks-like-xml = $clean.starts-with('<');
    if $looks-like-xml {
        with try-xml-parse($clean) -> $root-info {
            return parse-feed($root-info<doc>);
        }
        Syndicate::Stats.record-error;
        die "parse-feed: XML parsing failed — input is not valid XML";
    }

    with try-parse-json($clean) -> $parsed {
        my $feed = Syndicate::JSONFeed.new-from-hash(%$parsed);
        Syndicate::Stats.record-feed;
        return $feed;
    }
    Syndicate::Stats.record-error;
    die "parse-feed: unable to detect feed format — input is not valid XML or JSON";
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

multi sub parse-feed-with-format(Str $input --> List) is export {
    my $clean = $input.trim;
    $clean .= subst(/^\xFEFF/, '');
    die "parse-feed-with-format: empty input" unless $clean.chars;
    my $bytes = $clean.encode.bytes;
    die "parse-feed-with-format: input too large ($bytes bytes, max {MAX-FEED-SIZE})"
        if $bytes > MAX-FEED-SIZE;

    with try-xml-parse($clean) -> $root-info {
        my $format = feed-format($root-info<name>, $root-info<ver>);
        my $feed   = parse-feed($root-info<doc>);
        return ($format, $feed);
    }

    with try-parse-json($clean) -> $parsed {
        my $feed = Syndicate::JSONFeed.new-from-hash(%$parsed);
        Syndicate::Stats.record-feed;
        return (JSONFeedFmt, $feed);
    }
    Syndicate::Stats.record-error;
    die "parse-feed-with-format: unable to detect feed format — input is not valid XML or JSON";
}

multi sub parse-file(Str $path --> Syndicate::Feed:D) is export {
    my $size = try { $path.IO.s };
    die "File too large ($size bytes, max {MAX-FEED-SIZE})" if $size.defined && $size > MAX-FEED-SIZE;
    my $contents = try { slurp($path) };
    without $contents {
        die "Could not read file '$path': $!";
    }
    parse-feed($contents)
}

multi sub parse-file(IO::Path $path --> Syndicate::Feed:D) is export {
    parse-file($path.Str)
}

sub try-parse-json(Str $input) {
    my $parsed = try { from-json($input) };
    return Nil unless $parsed ~~ Hash
        && $parsed<version>.defined
        && $parsed<version>.starts-with(JSONFEED-VERSION-PREFIX);
    $parsed
}

sub try-xml-parse(Str $clean) {
    my $stripped = $clean.trim-leading;
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
