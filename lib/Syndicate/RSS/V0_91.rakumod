use v6.d;
use XML;
use DateTime::Format::RFC2822;
use Syndicate::Feed;
use Syndicate::RSS::V0_91::Item;
use Syndicate::Utils;

unit class Syndicate::RSS::V0_91:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed;

has Str $.language;
has Str $.copyright;
has Str $.managingEditor;
has Str $.webMaster;
has Str $.rating;
has Str $.docs;
has DateTime $.pubDate;
has DateTime $.lastBuildDate;
has %.image;
has %.textInput;
has @.skipHours;
has @.skipDays;

multi method new(Str $xml) {
    my $doc = XML::Document.new($xml);
    my $rss = $doc.root;
    die "Not an RSS feed" unless $rss.name eq "rss";
    my $ver = $rss.attribs<version> // "";
    die "Not RSS 0.91 (version: $ver)" unless $ver eq "0.91";
    my $channel = $rss.elements(:TAG<channel>)[0];
    die "No channel element" unless $channel;

    my $title   = get-text($channel, "title");
    my $link    = get-text($channel, "link");
    my $desc    = get-text($channel, "description");
    my $lang    = get-text-optional($channel, "language");
    my $cpy     = get-text-optional($channel, "copyright");
    my $me      = get-text-optional($channel, "managingEditor");
    my $wm      = get-text-optional($channel, "webMaster");
    my $rating  = get-text-optional($channel, "rating");
    my $docs    = get-text-optional($channel, "docs");
    my $pd      = parse-date-optional(get-text($channel, "pubDate"));
    my $lbd     = parse-date-optional(get-text($channel, "lastBuildDate"));

    my %image;
    with $channel.elements(:TAG<image>)[0] {
        %image<url>         = get-text($_, "url");
        %image<title>       = get-text($_, "title");
        %image<link>        = get-text($_, "link");
        %image<width>       = get-text-optional($_, "width");
        %image<height>      = get-text-optional($_, "height");
        %image<description> = get-text-optional($_, "description");
    }

    my %textInput;
    with $channel.elements(:TAG<textinput>)[0] {
        %textInput<title>       = get-text($_, "title");
        %textInput<description> = get-text($_, "description");
        %textInput<name>        = get-text($_, "name");
        %textInput<link>        = get-text($_, "link");
    }

    my @skipHours;
    with $channel.elements(:TAG<skipHours>)[0] {
        for .elements(:TAG<hour>) -> $h {
            @skipHours.push: $h.contents[0].text.Int;
        }
    }

    my @skipDays;
    with $channel.elements(:TAG<skipDays>)[0] {
        for .elements(:TAG<day>) -> $d {
            @skipDays.push: $d.contents[0].text;
        }
    }

    my @items;
    for $channel.elements(:TAG<item>) -> $item-elem {
        my $it = get-text($item-elem, "title");
        my $il = get-text($item-elem, "link");
        my $id = get-text-optional($item-elem, "description");
        @items.push: Syndicate::RSS::V0_91::Item.new(
            :title($it), :link($il), :summary($id)
        );
    }

    my %bless = :$title, :$link, :description($desc),
        :language($lang), :copyright($cpy),
        :managingEditor($me), :webMaster($wm),
        :rating($rating), :$docs,
        :image(%image), :textInput(%textInput);
    %bless<pubDate> = $pd if $pd ~~ DateTime;
    %bless<lastBuildDate> = $lbd if $lbd ~~ DateTime;
    self.bless(|%bless, :@items, :skipHours(@skipHours), :skipDays(@skipDays))
}

method XML {
    my $xml = XML::Element.new(:name<rss>, :attribs({:version('0.91')}));
    my $channel = XML::Element.new(:name<channel>);
    $xml.append: $channel;

    $channel.append: XML::Element.new(:name<title>, :nodes([$.title])) if $.title.defined;
    $channel.append: XML::Element.new(:name<link>, :nodes([$.link])) if $.link.defined;
    $channel.append: XML::Element.new(:name<description>, :nodes([$.description])) if $.description.defined;
    $channel.append: XML::Element.new(:name<language>, :nodes([$.language])) if $.language.defined;
    $channel.append: XML::Element.new(:name<rating>, :nodes([$.rating])) if $.rating.defined;
    $channel.append: XML::Element.new(:name<copyright>, :nodes([$.copyright])) if $.copyright.defined;
    $channel.append: XML::Element.new(:name<docs>, :nodes([$.docs])) if $.docs.defined;
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

    if %.image {
        my $img = XML::Element.new(:name<image>);
        $img.append: XML::Element.new(:name<title>, :nodes([%.image<title>]));
        $img.append: XML::Element.new(:name<url>, :nodes([%.image<url>]));
        $img.append: XML::Element.new(:name<link>, :nodes([%.image<link>]));
        $img.append: XML::Element.new(:name<width>, :nodes([%.image<width>])) if %.image<width>.defined;
        $img.append: XML::Element.new(:name<height>, :nodes([%.image<height>])) if %.image<height>.defined;
        $img.append: XML::Element.new(:name<description>, :nodes([%.image<description>])) if %.image<description>.defined;
        $channel.append: $img;
    }

    if %.textInput {
        my $ti = XML::Element.new(:name<textinput>);
        $ti.append: XML::Element.new(:name<title>, :nodes([%.textInput<title>]));
        $ti.append: XML::Element.new(:name<description>, :nodes([%.textInput<description>]));
        $ti.append: XML::Element.new(:name<name>, :nodes([%.textInput<name>]));
        $ti.append: XML::Element.new(:name<link>, :nodes([%.textInput<link>]));
        $channel.append: $ti;
    }

    if @.skipHours {
        my $sh = XML::Element.new(:name<skipHours>);
        $sh.append: XML::Element.new(:name<hour>, :nodes([~$_])) for @.skipHours;
        $channel.append: $sh;
    }

    if @.skipDays {
        my $sd = XML::Element.new(:name<skipDays>);
        $sd.append: XML::Element.new(:name<day>, :nodes([$_])) for @.skipDays;
        $channel.append: $sd;
    }

    $channel.append: $_.XML for @.items;

    return $xml;
}

method Str { ~self.XML }
