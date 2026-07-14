use v6.d;

use Syndicate::Item;
use Syndicate::Feed;
use Syndicate::Stats;
use Syndicate::RSS;
use Syndicate::RSS::Item;
use Syndicate::RSS::V0_91;
use Syndicate::RSS::V0_91::Item;
use Syndicate::RSS::V1_0;
use Syndicate::RSS::V1_0::Item;
use Syndicate::Atom;
use Syndicate::Atom::Item;
use Syndicate::JSONFeed;
use Syndicate::JSONFeed::Item;
use Syndicate::Utils;
use Syndicate::Builder::Feed;
use Syndicate::Builder::Entry;
use Syndicate::Parse;
use Syndicate::Extension::DublinCore;
use Syndicate::Extension::MediaRSS;
use Syndicate::Extension::ITunes;
use Syndicate::Discovery;

unit class Syndicate:ver<0.0.1>:auth<zef:sasha>;

sub parse(Str $input --> Syndicate::Feed:D) is export {
    parse-feed($input)
}

my constant MAX-FEED-SIZE = 10 * 1024 * 1024;

sub sanitize-input(Str $input --> Str) {
    my $clean = $input.trim;
    $clean .= subst(/^\xFEFF/, '');
    die "empty input" unless $clean.chars;
    my $bytes = $clean.encode.bytes;
    die "input too large ($bytes bytes, max {MAX-FEED-SIZE})" if $bytes > MAX-FEED-SIZE;
    $clean
}

sub parse-rss(Str $xml --> Syndicate::RSS) is export {
    Syndicate::RSS.new(sanitize-input($xml))
}

sub parse-atom(Str $xml --> Syndicate::Atom) is export {
    Syndicate::Atom.new(sanitize-input($xml))
}

sub parse-json(Str $json --> Syndicate::JSONFeed) is export {
    Syndicate::JSONFeed.new(sanitize-input($json))
}

sub parse-rss1(Str $xml --> Syndicate::RSS::V1_0) is export {
    Syndicate::RSS::V1_0.new(sanitize-input($xml))
}

sub parse-rss091(Str $xml --> Syndicate::RSS::V0_91) is export {
    Syndicate::RSS::V0_91.new(sanitize-input($xml))
}

=begin pod

=head1 NAME

Syndicate - Syndication feed parser and generator

=head1 SYNOPSIS

=begin code :lang<raku>
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
=end code

=head1 DESCRIPTION

Syndicate supports parsing and generation of RSS 2.0, RSS 0.91, RSS 1.0,
Atom 1.0, and JSON Feed 1.1. Provides a uniform API via L<C<Syndicate::Feed>|rakudoc:Syndicate::Feed>
and L<C<Syndicate::Item>|rakudoc:Syndicate::Item> roles, a format-agnostic builder, feed discovery,
and extension support (Dublin Core, Media RSS, iTunes).

B<Security note:> The C<XML> module's behavior on entity expansion is
version-dependent. In multi-tenant or untrusted-input scenarios, consider
pre-scanning input or using an external XML parser with explicit XXE and
billion-laughs protections. Feed URLs fetched via L<C<Syndicate::Discovery>|rakudoc:Syndicate::Discovery>
are restricted to http/https schemes.

B<Note:> The C<parse-rss>, C<parse-atom>, C<parse-json>, C<parse-rss1>, and
C<parse-rss091> subs call format constructors directly, bypassing the BOM
stripping, size limit, and input trimming that L<C<parse-feed>|rakudoc:Syndicate::Parse> enforces.
For untrusted input, use C<parse()> instead of the format-specific subs.

=head1 EXPORTED SUBS

=head2 C<parse(Str $input)>

Auto-detect format and parse, returning a C<Syndicate::Feed>-compatible object.

=head2 C<parse-rss(Str $xml)>

Parse RSS 2.0 XML, returning C<Syndicate::RSS>.

=head2 C<parse-atom(Str $xml)>

Parse Atom 1.0 XML, returning C<Syndicate::Atom>.

=head2 C<parse-json(Str $json)>

Parse JSON Feed, returning C<Syndicate::JSONFeed>.

=head2 C<parse-rss1(Str $xml)>

Parse RSS 1.0 XML, returning C<Syndicate::RSS::V1_0>.

=head2 C<parse-rss091(Str $xml)>

Parse RSS 0.91 XML, returning C<Syndicate::RSS::V0_91>.

=end pod
