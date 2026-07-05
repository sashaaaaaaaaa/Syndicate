use v6.d;
use XML;
use Syndicate::RSS;
use Syndicate::RSS::V0_91;
use Syndicate::RSS::V1_0;
use Syndicate::Atom;
use Syndicate::JSONFeed;
use Syndicate::Stats;
use JSON::Fast;

unit module Syndicate::Parse:ver<0.0.1>:auth<zef:sasha>;

enum FeedFormat is export <Atom RSS2 RSS091 RSS1 JSONFeedFmt>;

multi sub feed-format(Str $input --> FeedFormat) is export {
    my $clean = $input.trim;
    die "Empty input" unless $clean.chars;

    unless $clean.starts-with('{') || $clean.starts-with('[') {
        my $root = root-element($clean);
        if $root {
            return feed-format($root<name>, $root<ver>);
        }
    }

    my $parsed = try { from-json($clean) };
    die "Unable to detect feed format: input is not valid XML or JSON"
        unless $parsed ~~ Hash
            && $parsed<version>.defined
            && $parsed<version>.starts-with('https://jsonfeed.org/version/');
    JSONFeedFmt
}

multi sub feed-format(Str $name, Str $ver) {
    given $name {
        when 'feed'   { return Atom }
        when 'rss'    { return $ver.starts-with('0.9') ?? RSS091 !! RSS2 }
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
    unless $clean.starts-with('{') || $clean.starts-with('[') {
        my $root-info = root-element($clean);
        if $root-info {
            return parse-feed($root-info<doc>);
        }
    }
    my $parsed = try { from-json($clean) };
    unless $parsed ~~ Hash
        && $parsed<version>.defined
        && $parsed<version>.starts-with('https://jsonfeed.org/version/') {
        Syndicate::Stats.record-error;
        die "Unable to detect feed format: input is not valid XML or JSON";
    }
    my $feed = Syndicate::JSONFeed.new-from-hash(%$parsed);
    Syndicate::Stats.record-feed;
    return $feed;
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

multi sub parse-file(Str $path --> Syndicate::Feed:D) is export {
    parse-feed(slurp($path))
}

multi sub parse-file(IO::Path $path --> Syndicate::Feed:D) is export {
    parse-file($path.Str)
}

sub root-element(Str $input) {
    my $doc = try { XML::Document.new($input) };
    return Nil unless $doc;
    my $root = $doc.root;
    my $name = $root.name;
    my $ver = $root.attribs<version> // "";
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
=end code

=head1 DESCRIPTION

Provides auto-detection of feed format from raw input and dispatching
to the appropriate parser class.

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

=head2 C<parse-file(Str $path)> / C<parse-file(IO::Path $path)>

Reads a file from disk and parses it as a feed (auto-detected format).
Throws if the file cannot be read or is not valid feed content.
Assumes UTF-8 encoding. For non-UTF-8 feed files, read the content
manually with the appropriate encoding and pass to C<parse-feed>.

=for code :lang<raku>
my $feed = parse-file("feed.xml");
my $feed = parse-file("feed.xml".IO);

=end pod
