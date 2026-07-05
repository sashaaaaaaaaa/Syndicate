use v6.d;
use XML;
use Syndicate::Feed;
use Syndicate::RSS::Common;
use Syndicate::RSS::Item;
use DateTime::Format::RFC2822;
my constant $RFC2822 = DateTime::Format::RFC2822.new;
use Syndicate::Utils;
use Syndicate::Extension::DublinCore;
use Syndicate::Extension::MediaRSS;
use Syndicate::Extension::ITunes;
use Syndicate::Stats;

my constant NS-CONTENT     = 'http://purl.org/rss/1.0/modules/content/';
my constant NS-ATOM        = 'http://www.w3.org/2005/Atom';
my constant ONE-WEEK-MINUTES = 10080;

unit class Syndicate::RSS:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed does Syndicate::RSS::Common;

has Str $.copyright;
has Str $.managingEditor;
has Str $.webMaster;
has DateTime $.pubDate;
has DateTime $.lastBuildDate;
has @.categories of Str;
has Str $.docs;
has Int $.ttl;
has %.image of Str;
has Str $.itunes-author;
has Str $.itunes-summary;
has Str $.atom-self-link;
has Bool $!needs-dc;
has Bool $!needs-media;
has Bool $!needs-content;
has Bool $!needs-itunes;

submethod TWEAK {
    self!set-namespace-flags;
}

multi method new(XML::Document $doc) {
    my $rss = $doc.root;
    die "Not an RSS feed" unless $rss.name eq "rss";
    my $ver = $rss.attribs<version> // "2.0";
    die "Unsupported RSS version: $ver" unless $ver eq "2.0";
    my $channel = $rss.elements(:TAG<channel>)[0];
    die "No channel element" unless $channel;

    my $title   = get-text($channel, "title");
    my $link    = get-text($channel, "link");
    my $desc    = get-text($channel, "description");
    my $lang    = get-text-optional($channel, "language");
    my $cpy     = get-text-optional($channel, "copyright");
    my $me      = get-text-optional($channel, "managingEditor");
    my $wm      = get-text-optional($channel, "webMaster");
    my $pd      = parse-date-optional(get-text-optional($channel, "pubDate"));
    my $lbd     = parse-date-optional(get-text-optional($channel, "lastBuildDate"));
    my @categories;
    for $channel.elements(:TAG<category>) -> $c {
        with $c.contents[0] -> $t {
            my $text = $t.?text // "";
            @categories.push: decode-entities($text) if $text.chars;
        }
    }
    my $gen     = get-text-optional($channel, "generator");
    my $docs    = get-text-optional($channel, "docs");
    my $ttl-str = get-text-optional($channel, "ttl");
    my $it-author  = get-itunes-text($channel, "author");
    my $it-summary = get-itunes-text($channel, "summary");

    my %image = self.parse-image($channel);

    my $atom-self-link = Str;
    for $channel.elements(:TAG<atom:link>) -> $l {
        if ($l.attribs<rel> // "") eq "self" {
            $atom-self-link = $l.attribs<href> // Str;
            last;
        }
    }

    my @items;
    for $channel.elements(:TAG<item>) -> $item-elem {
        @items.push: Syndicate::RSS::Item.from-xml($item-elem);
    }

    my %bless = :$title, :$link, :description($desc),
        :language($lang), :copyright($cpy),
        :managingEditor($me), :webMaster($wm),
        :generator($gen), :docs($docs),
        :image(%image),
        :itunes-author($it-author), :itunes-summary($it-summary),
        :$atom-self-link;
    %bless<pubDate> = $pd if $pd ~~ DateTime;
    %bless<lastBuildDate> = $lbd if $lbd ~~ DateTime;
    if $ttl-str.defined && $ttl-str.chars {
        %bless<ttl> = try { $ttl-str.Int };
        unless %bless<ttl>.defined {
            note "Invalid ttl value: $ttl-str";
        }
        with %bless<ttl> {
            note "ttl of $_ minutes exceeds recommended maximum of {ONE-WEEK-MINUTES} (1 week)" if $_ > ONE-WEEK-MINUTES;
        }
    }
    CATCH {
        Syndicate::Stats.record-error;
        .rethrow;
    }
    # CATCH covers the entire method scope (Raku phaser semantics),
    # not just the single self.bless call below.
    self.bless(|%bless, :@categories, :@items)
}

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    unless $doc {
        Syndicate::Stats.record-error;
        die "Invalid RSS XML: $!";
    }
    self.new($doc)
}

method !set-namespace-flags {
    my $feed-itunes = $!itunes-author.defined || $!itunes-summary.defined;
    ($!needs-dc, $!needs-media, $!needs-itunes, $!needs-content) = self!set-item-flags;
    $!needs-itunes ||= $feed-itunes;
}

method XML {
    my $xml = XML::Element.new(:name<rss>, :attribs({:version('2.0')}));
    add-dc-declaration($xml)    if $!needs-dc;
    add-media-declaration($xml) if $!needs-media;
    add-itunes-declaration($xml) if $!needs-itunes;
    $xml.attribs{'xmlns:content'} = NS-CONTENT if $!needs-content;
    if $.atom-self-link.defined {
        $xml.attribs{'xmlns:atom'} = NS-ATOM;
    }
    my $channel = XML::Element.new(:name<channel>);
    $xml.append: $channel;

    add-element($channel, "title",          $.title);
    add-element($channel, "link",           $.link);
    add-element($channel, "description",    $.description);
    add-element($channel, "language",       $.language);
    add-element($channel, "copyright",      $.copyright);
    add-element($channel, "managingEditor", $.managingEditor);
    add-element($channel, "webMaster",      $.webMaster);
    add-itunes-element($channel, "author", $.itunes-author) if $.itunes-author.defined;
    add-itunes-element($channel, "summary", $.itunes-summary) if $.itunes-summary.defined;

    if $.pubDate.defined {
        $channel.append: XML::Element.new(:name<pubDate>, :nodes([$RFC2822.to-string($.pubDate)]));
    }
    if $.lastBuildDate.defined {
        $channel.append: XML::Element.new(:name<lastBuildDate>, :nodes([$RFC2822.to-string($.lastBuildDate)]));
    }

    add-element($channel, "category",  $_) for @.categories;
    add-element($channel, "generator", $.generator);
    add-element($channel, "docs",      $.docs);
    add-element($channel, "ttl",       ~$.ttl) if $.ttl.defined;

    self.build-xml-image($channel, %.image) if %.image<url>.defined || %.image<title>.defined;

    if $.atom-self-link.defined {
        $channel.append: XML::Element.new(
            :name<atom:link>,
            :attribs({ :href(encode-entities($.atom-self-link)), :rel<self>, :type('application/rss+xml') })
        );
    }

    $channel.append: $_.XML for @.items;

    return $xml;
}

=begin pod

=head1 NAME

Syndicate::RSS - RSS 2.0 feed

=head1 SYNOPSIS

=begin code :lang<raku>
my $feed = Syndicate::RSS.new($xml-string);
my $feed = Syndicate::RSS.new(:title("My Feed"), :link("https://example.com"), ...);
say ~$feed;  # XML output
=end code

=head1 DESCRIPTION

Parses and generates RSS 2.0 feeds. Does L<C<Syndicate::Feed>|rakudoc:Syndicate::Feed>
and L<C<Syndicate::RSS::Common>|rakudoc:Syndicate::RSS::Common>.

Supports iTunes podcast and Media RSS extensions via the extension registry.

=head1 ATTRIBUTES

=item C<$.title>, C<$.link>, C<$.description> - from Feed role
=item C<$.generator>, C<$.language> - from Feed role
=item C<$.copyright> - Copyright notice
=item C<$.managingEditor> - Managing editor email
=item C<$.webMaster> - Webmaster email
=item C<$.pubDate> - Publication date (L<C<DateTime>|rakudoc:DateTime>)
=item C<$.lastBuildDate> - Last build date (L<C<DateTime>|rakudoc:DateTime>)
=item C<@.categories> - Feed categories
=item C<$.docs> - Documentation URL
=item C<$.ttl> - Time to live (minutes)
=item C<%.image> - Feed image hash (url, title, link, width, height)
=item C<$.itunes-author> - iTunes author
=item C<$.itunes-summary> - iTunes summary

=head1 METHODS

=item C<new(Str $xml)> - Parse RSS 2.0 XML string
=item C<new(:$title, :$link, ...)> - Construct with named args
=item C<XML> - Returns L<C<XML::Element>|rakudoc:XML::Element>
=item C<Str> - Returns XML string

=end pod
