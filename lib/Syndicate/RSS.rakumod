use v6.d;
use XML;
use DateTime::Format::RFC2822;
use Syndicate::Feed;
use Syndicate::RSS::Item;
use Syndicate::Utils;
use Syndicate::Extension::DublinCore;
use Syndicate::Extension::MediaRSS;

unit class Syndicate::RSS:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed;

has Str $.language;
has Str $.copyright;
has Str $.managingEditor;
has Str $.webMaster;
has DateTime $.pubDate;
has DateTime $.lastBuildDate;
has Str $.category;
has Str $.generator;
has Str $.docs;
has Int $.ttl;
has %.image;
has %.textInput;
has @.skipHours;
has @.skipDays;

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

    my %image;
    with $channel.elements(:TAG<image>)[0] {
        %image<url>         = get-text($_, "url");
        %image<title>       = get-text($_, "title");
        %image<link>        = get-text($_, "link");
        %image<width>       = get-text-optional($_, "width");
        %image<height>      = get-text-optional($_, "height");
        %image<description> = get-text-optional($_, "description");
    }

    my @items;
    for $channel.elements(:TAG<item>) -> $item-elem {
        @items.push: Syndicate::RSS::Item.new-from-xml($item-elem);
    }

    my %bless = :$title, :$link, :description($desc),
        :language($lang), :copyright($cpy),
        :managingEditor($me), :webMaster($wm),
        :category($cat), :generator($gen), :docs($docs),
        :image(%image);
    %bless<pubDate> = $pd if $pd ~~ DateTime;
    %bless<lastBuildDate> = $lbd if $lbd ~~ DateTime;
    %bless<ttl> = $ttl-str.Int if $ttl-str.defined && $ttl-str.chars;
    self.bless(|%bless, :@items)
}

method XML {
    my $xml = XML::Element.new(:name<rss>, :attribs({:version('2.0')}));
    add-dc-declaration($xml);
    add-media-declaration($xml);
    my $channel = XML::Element.new(:name<channel>);
    $xml.append: $channel;

    $channel.append: XML::Element.new(:name<title>, :nodes([$.title])) if $.title.defined;
    $channel.append: XML::Element.new(:name<link>, :nodes([$.link])) if $.link.defined;
    $channel.append: XML::Element.new(:name<description>, :nodes([$.description])) if $.description.defined;
    $channel.append: XML::Element.new(:name<language>, :nodes([$.language])) if $.language.defined;
    $channel.append: XML::Element.new(:name<copyright>, :nodes([$.copyright])) if $.copyright.defined;
    $channel.append: XML::Element.new(:name<managingEditor>, :nodes([$.managingEditor])) if $.managingEditor.defined;
    $channel.append: XML::Element.new(:name<webMaster>, :nodes([$.webMaster])) if $.webMaster.defined;

    if $.pubDate.defined {
        my $f = DateTime::Format::RFC2822.new;
        $channel.append: XML::Element.new(:name<pubDate>, :nodes([$f.to-string($.pubDate)]));
    }
    if $.lastBuildDate.defined {
        my $f = DateTime::Format::RFC2822.new;
        $channel.append: XML::Element.new(:name<lastBuildDate>, :nodes([$f.to-string($.lastBuildDate)]));
    }

    $channel.append: XML::Element.new(:name<category>, :nodes([$.category])) if $.category.defined;
    $channel.append: XML::Element.new(:name<generator>, :nodes([$.generator])) if $.generator.defined;
    $channel.append: XML::Element.new(:name<docs>, :nodes([$.docs])) if $.docs.defined;
    $channel.append: XML::Element.new(:name<ttl>, :nodes([~$.ttl])) if $.ttl.defined;

    if %.image {
        my $img = XML::Element.new(:name<image>);
        $img.append: XML::Element.new(:name<url>, :nodes([%.image<url>]));
        $img.append: XML::Element.new(:name<title>, :nodes([%.image<title>]));
        $img.append: XML::Element.new(:name<link>, :nodes([%.image<link>]));
        $channel.append: $img;
    }

    $channel.append: $_.XML for @.items;

    return $xml;
}

method Str { ~self.XML }
