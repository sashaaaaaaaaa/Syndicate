use v6.d;

use Syndicate::Item;
use Syndicate::Feed;
use Syndicate::Config;
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

sub parse(Str $input --> Any) is export {
    parse-feed($input)
}

sub parse-rss(Str $xml) is export {
    Syndicate::RSS.new($xml)
}

sub parse-atom(Str $xml) is export {
    Syndicate::Atom.new($xml)
}

sub parse-json(Str $json) is export {
    Syndicate::JSONFeed.new($json)
}

sub parse-rss1(Str $xml) is export {
    Syndicate::RSS::V1_0.new($xml)
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

=head1 EXPORTED SUBS

=head2 C<parse(Str $input)>

Auto-detect format and parse, returning a C<Syndicate::Feed>-compatible object.

=head2 C<parse-rss(Str $xml)>

Parse RSS 2.0 XML, returning C<Syndicate::RSS>.

=head2 C<parse-atom(Str $xml)>

Parse Atom 1.0 XML, returning C<Syndicate::Atom>.

=end pod
