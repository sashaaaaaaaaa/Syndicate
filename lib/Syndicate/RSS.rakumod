use v6.d;
use XML;
use DateTime::Format::RFC2822;
use Syndicate::Feed;
use Syndicate::RSS::Common;
use Syndicate::RSS::Item;
use Syndicate::Utils;
use Syndicate::Extension::DublinCore;
use Syndicate::Extension::MediaRSS;
use Syndicate::Extension::ITunes;

my constant $RFC2822 = DateTime::Format::RFC2822.new;

unit class Syndicate::RSS:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed does Syndicate::RSS::Common;

has Str $.copyright;
has Str $.managingEditor;
has Str $.webMaster;
has DateTime $.pubDate;
has DateTime $.lastBuildDate;
has Str $.category;
has Str $.docs;
has Int $.ttl;
has %.image;
has Str $.itunes-author;
has Str $.itunes-summary;
has Str $.atom-self-link;

multi method new(Str $xml) {
    my $doc = XML::Document.new($xml);
    my $rss = $doc.root;
    die "Not an RSS feed" unless $rss.name eq "rss";
    my $channel = $rss.elements(:TAG<channel>)[0];
    die "No channel element" unless $channel;

    my $title   = get-text($channel, "title");
    my $link    = get-text($channel, "link");
    my $desc    = get-text($channel, "description");
    my $lang    = get-text-optional($channel, "language");
    my $cpy     = get-text-optional($channel, "copyright");
    my $me      = get-text-optional($channel, "managingEditor");
    my $wm      = get-text-optional($channel, "webMaster");
    my $pd      = parse-date-optional(get-text($channel, "pubDate"));
    my $lbd     = parse-date-optional(get-text($channel, "lastBuildDate"));
    my $cat     = get-text-optional($channel, "category");
    my $gen     = get-text-optional($channel, "generator");
    my $docs    = get-text-optional($channel, "docs");
    my $ttl-str = get-text-optional($channel, "ttl");
    my $it-author  = get-itunes-text($channel, "author");
    my $it-summary = get-itunes-text($channel, "summary");

    my %image = self.parse-image($channel);

    my @items;
    for $channel.elements(:TAG<item>) -> $item-elem {
        @items.push: Syndicate::RSS::Item.new-from-xml($item-elem);
    }

    my %bless = :$title, :$link, :description($desc),
        :language($lang), :copyright($cpy),
        :managingEditor($me), :webMaster($wm),
        :category($cat), :generator($gen), :docs($docs),
        :image(%image),
        :itunes-author($it-author), :itunes-summary($it-summary);
    %bless<pubDate> = $pd if $pd ~~ DateTime;
    %bless<lastBuildDate> = $lbd if $lbd ~~ DateTime;
    %bless<ttl> = $ttl-str.Int if $ttl-str.defined && $ttl-str.chars;
    self.bless(|%bless, :@items)
}

method XML {
    my $xml = XML::Element.new(:name<rss>, :attribs({:version('2.0')}));
    add-dc-declaration($xml);
    add-media-declaration($xml);
    add-itunes-declaration($xml);
    if $.atom-self-link.defined {
        $xml.attribs{'xmlns:atom'} = 'http://www.w3.org/2005/Atom';
    }
    my $channel = XML::Element.new(:name<channel>);
    $xml.append: $channel;

    $channel.append: XML::Element.new(:name<title>, :nodes([$.title])) if $.title.defined;
    $channel.append: XML::Element.new(:name<link>, :nodes([$.link])) if $.link.defined;
    $channel.append: XML::Element.new(:name<description>, :nodes([$.description])) if $.description.defined;
    $channel.append: XML::Element.new(:name<language>, :nodes([$.language])) if $.language.defined;
    $channel.append: XML::Element.new(:name<copyright>, :nodes([$.copyright])) if $.copyright.defined;
    $channel.append: XML::Element.new(:name<managingEditor>, :nodes([$.managingEditor])) if $.managingEditor.defined;
    $channel.append: XML::Element.new(:name<webMaster>, :nodes([$.webMaster])) if $.webMaster.defined;
    add-itunes-element($channel, "author", $.itunes-author) if $.itunes-author.defined;
    add-itunes-element($channel, "summary", $.itunes-summary) if $.itunes-summary.defined;

    if $.pubDate.defined {
        $channel.append: XML::Element.new(:name<pubDate>, :nodes([$RFC2822.to-string($.pubDate)]));
    }
    if $.lastBuildDate.defined {
        $channel.append: XML::Element.new(:name<lastBuildDate>, :nodes([$RFC2822.to-string($.lastBuildDate)]));
    }

    $channel.append: XML::Element.new(:name<category>, :nodes([$.category])) if $.category.defined;
    $channel.append: XML::Element.new(:name<generator>, :nodes([$.generator])) if $.generator.defined;
    $channel.append: XML::Element.new(:name<docs>, :nodes([$.docs])) if $.docs.defined;
    $channel.append: XML::Element.new(:name<ttl>, :nodes([~$.ttl])) if $.ttl.defined;

    self.build-xml-image($channel, %.image);

    if $.atom-self-link.defined {
        $channel.append: XML::Element.new(
            :name<atom:link>,
            :attribs({ :href($.atom-self-link), :rel<self>, :type('application/rss+xml') })
        );
    }

    $channel.append: $_.XML for @.items;

    return $xml;
}

method Str { '<?xml version="1.0" encoding="UTF-8"?>' ~ "\n" ~ ~self.XML }

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
=item C<$.category> - Feed category
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
