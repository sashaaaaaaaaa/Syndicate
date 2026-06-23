use v6.d;
use XML;
use Syndicate::RSS;
use Syndicate::RSS::V0_91;
use Syndicate::RSS::V1_0;
use Syndicate::Atom;
use Syndicate::JSONFeed;
use Syndicate::Stats;

unit module Syndicate::Parse:ver<0.0.1>:auth<zef:sasha>;

enum FeedFormat is export <Atom RSS2 RSS091 RSS1 JSONFeedFmt>;

sub feed-format(Str $input --> FeedFormat) is export {
    my $clean = $input.trim;
    die "Empty input" unless $clean.chars;

    return JSONFeedFmt if $clean.starts-with('{');

    my $root = root-element($clean);
    die "Unknown feed format: cannot find root element" unless $root.defined;

    given $root<name> {
        when 'feed'   { return Atom }
        when 'rss'    {
            return $root<ver> eq '0.91' ?? RSS091 !! RSS2
        }
        when 'rdf:RDF' | 'RDF' { return RSS1 }
        default { die "Unknown feed format: <$_>" }
    }
}

sub parse-feed(Str $input --> Any) is export {
    my $feed = do given feed-format($input) {
        when Atom    { Syndicate::Atom.new($input) }
        when RSS2    { Syndicate::RSS.new($input) }
        when RSS091  { Syndicate::RSS::V0_91.new($input) }
        when RSS1    { Syndicate::RSS::V1_0.new($input) }
        when JSONFeedFmt { Syndicate::JSONFeed.new($input) }
        default { die "Unhandled feed format: '$_'" }
    }
    CATCH {
        Syndicate::Stats.record-error;
        die $_;
    }
    Syndicate::Stats.record-feed;
    $feed
}

sub root-element(Str $input) {
    my $doc = try { XML::Document.new($input.trim) };
    return Nil unless $doc;
    my $root = $doc.root;
    my $name = $root.name;
    my $ver = $root.attribs<version> // "";
    %(:$name, :$ver)
}

=begin pod

=head1 NAME

Syndicate::Parse - Feed format detection and parsing dispatcher

=head1 SYNOPSIS

=begin code :lang<raku>
use Syndicate::Parse;

my $format = feed-format($input);       # Detect format
my $feed   = parse-feed($input);        # Parse any format
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

=end pod
