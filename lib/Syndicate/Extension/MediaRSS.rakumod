use v6.d;
use XML;
use Syndicate::Extensions;

unit module Syndicate::Extension::MediaRSS:ver<0.0.1>:auth<zef:sasha>;

register-ext(
    parse => sub ($elem, %attrs) {
        %attrs<media-contents>    = get-media-contents($elem);
        %attrs<media-thumbnails>  = get-media-thumbnails($elem);
        %attrs<media-title>       = get-media-text($elem, "title");
        %attrs<media-description> = get-media-text($elem, "description");
    },
    generate => sub ($xml, $item) {
        add-media-content-element($xml, $_) for @($item.media-contents);
        add-media-thumbnail-element($xml, $_) for @($item.media-thumbnails);
        $xml.append: XML::Element.new(:name<media:title>, :nodes([$item.media-title])) if $item.media-title.defined;
        $xml.append: XML::Element.new(:name<media:description>, :nodes([$item.media-description])) if $item.media-description.defined;
    }
);

sub get-media-text($parent, Str $tag --> Str) is export {
    with $parent.elements(:TAG("media:$tag"))[0] -> $e {
        with $e.contents[0] -> $t {
            return $t.text // "";
        }
    }
    Str
}

sub get-media-contents($parent --> Array) is export {
    my @contents;
    for $parent.elements(:TAG<media:content>) -> $e {
        my %c;
        %c<url>      = $e.attribs<url>      // Str;
        %c<type>     = $e.attribs<type>     // Str;
        %c<medium>   = $e.attribs<medium>   // Str;
        %c<duration> = $e.attribs<duration> // Str;
        %c<fileSize> = $e.attribs<fileSize> // Str;
        %c<width>    = $e.attribs<width>    // Str;
        %c<height>   = $e.attribs<height>   // Str;
        @contents.push: %c;
    }
    @contents
}

sub get-media-thumbnails($parent --> Array) is export {
    my @thumbs;
    for $parent.elements(:TAG<media:thumbnail>) -> $e {
        my %t;
        %t<url>    = $e.attribs<url>    // Str;
        %t<width>  = $e.attribs<width>  // Str;
        %t<height> = $e.attribs<height> // Str;
        @thumbs.push: %t;
    }
    @thumbs
}

sub add-media-declaration(XML::Element $root --> Nil) is export {
    $root.attribs{'xmlns:media'} = 'http://search.yahoo.com/mrss/'
        unless $root.attribs{'xmlns:media'}.defined;
}

sub add-media-content-element(XML::Element $parent, %content --> Nil) is export {
    my $e = XML::Element.new(:name<media:content>);
    $e.attribs<url>      = %content<url>      if %content<url>.defined;
    $e.attribs<type>     = %content<type>     if %content<type>.defined;
    $e.attribs<medium>   = %content<medium>   if %content<medium>.defined;
    $e.attribs<duration> = %content<duration> if %content<duration>.defined;
    $e.attribs<fileSize> = %content<fileSize> if %content<fileSize>.defined;
    $e.attribs<width>    = %content<width>    if %content<width>.defined;
    $e.attribs<height>   = %content<height>   if %content<height>.defined;
    $parent.append: $e;
}

sub add-media-thumbnail-element(XML::Element $parent, %thumb --> Nil) is export {
    my $e = XML::Element.new(:name<media:thumbnail>);
    $e.attribs<url>    = %thumb<url>    if %thumb<url>.defined;
    $e.attribs<width>  = %thumb<width>  if %thumb<width>.defined;
    $e.attribs<height> = %thumb<height> if %thumb<height>.defined;
    $parent.append: $e;
}
