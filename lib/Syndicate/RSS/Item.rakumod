use v6.d;
use XML;
use DateTime::Format::RFC2822;
use Syndicate::Item;
use Syndicate::Utils;
use Syndicate::Extensions;

unit class Syndicate::RSS::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

has Str $.guid;
has Bool $.guid-is-permalink = True;
has Str $.category;
has Str $.comments;
has %.enclosure;
has Str $.source;
has @.media-contents;
has @.media-thumbnails;
has Str $.media-title;
has Str $.media-description;
has Str $.itunes-author;
has Str $.itunes-summary;
has Str $.itunes-duration;

multi method new(Str $xml) {
    my $doc = XML::Document.new($xml);
    self.new-from-xml($doc.root)
}

multi method new(XML::Element $xml-elem) {
    self.new-from-xml($xml-elem)
}

proto method new-from-xml(|) {*}
multi method new-from-xml(XML::Element $item-elem) {
    my $title   = get-text($item-elem, "title");
    my $link    = get-text($item-elem, "link");
    my $desc    = get-text($item-elem, "description");
    my $author  = get-text-optional($item-elem, "author");
    my $cat     = get-text-optional($item-elem, "category");
    my $comment = get-text-optional($item-elem, "comments");
    my $pubdate = parse-date-optional(get-text($item-elem, "pubDate"));
    my $source  = get-text-optional($item-elem, "source");

    my $guid-elem = $item-elem.elements(:TAG<guid>)[0];
    my $guid = Str;
    my $guid-is-permalink = True;
    with $guid-elem {
        $guid = .contents[0].text // Str;
        $guid-is-permalink = (.attribs<isPermaLink> // "true") eq "true";
    }

    my %enclosure;
    with $item-elem.elements(:TAG<enclosure>)[0] {
        %enclosure<url>    = .attribs<url>    // Str;
        %enclosure<length> = .attribs<length> // Str;
        %enclosure<type>   = .attribs<type>   // Str;
    }

    my %extra;
    run-parsers($item-elem, %extra);
    $author //= %extra<author> // Str;

    my @media-contents    = @(%extra<media-contents>    // []);
    my @media-thumbnails  = @(%extra<media-thumbnails>  // []);
    my $media-title       = %extra<media-title>         // Str;
    my $media-description = %extra<media-description>   // Str;

    my %bless = :$title, :$link, :summary($desc),
        :$author,
        :$guid, :guid-is-permalink($guid-is-permalink),
        :category($cat), :comments($comment),
        :enclosure(%enclosure), :source($source),
        :media-title($media-title), :media-description($media-description),
        :itunes-author(%extra<itunes-author> // Str),
        :itunes-summary(%extra<itunes-summary> // Str),
        :itunes-duration(%extra<itunes-duration> // Str);
    %bless<updated> = $pubdate if $pubdate ~~ DateTime;
    self.bless(|%bless, :@media-contents, :@media-thumbnails)
}

method XML {
    my $xml = XML::Element.new(:name<item>);
    $xml.append: XML::Element.new(:name<title>, :nodes([$.title])) if $.title.defined;
    $xml.append: XML::Element.new(:name<link>, :nodes([$.link])) if $.link.defined;
    if $.guid.defined {
        my $guid-elem = XML::Element.new(:name<guid>, :nodes([$.guid]));
        $guid-elem.attribs<isPermaLink> = $.guid-is-permalink ?? "true" !! "false";
        $xml.append: $guid-elem;
    }
    $xml.append: XML::Element.new(:name<description>, :nodes([$.summary])) if $.summary.defined;
    if $.updated.defined {
        my $f = DateTime::Format::RFC2822.new;
        $xml.append: XML::Element.new(:name<pubDate>, :nodes([$f.to-string($.updated)]));
    }
    $xml.append: XML::Element.new(:name<author>, :nodes([$.author])) if $.author.defined;
    $xml.append: XML::Element.new(:name<category>, :nodes([$.category])) if $.category.defined;
    $xml.append: XML::Element.new(:name<comments>, :nodes([$.comments])) if $.comments.defined;
    if %.enclosure {
        my $enc = XML::Element.new(:name<enclosure>);
        $enc.attribs<url>    = %.enclosure<url>    // "";
        $enc.attribs<length> = %.enclosure<length> // "0";
        $enc.attribs<type>   = %.enclosure<type>   // "";
        $xml.append: $enc;
    }
    $xml.append: XML::Element.new(:name<source>, :nodes([$.source])) if $.source.defined;

    run-generators($xml, self);

    return $xml;
}

method Str { ~self.XML }
