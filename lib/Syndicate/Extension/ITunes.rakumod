use v6.d;
use XML;
use Syndicate::Extensions;

unit module Syndicate::Extension::ITunes:ver<0.0.1>:auth<zef:sasha>;

register-ext(
    parse => sub ($elem, %attrs) {
        %attrs<itunes-author>   = get-itunes-text($elem, "author");
        %attrs<itunes-summary>  = get-itunes-text($elem, "summary");
        %attrs<itunes-duration> = get-itunes-duration($elem);
    },
    generate => sub ($xml, $item) {
        add-itunes-element($xml, "author",   $item.itunes-author)   if $item.itunes-author.defined;
        add-itunes-element($xml, "summary",  $item.itunes-summary)  if $item.itunes-summary.defined;
        add-itunes-element($xml, "duration", $item.itunes-duration) if $item.itunes-duration.defined;
    }
);

my constant NS = 'http://www.itunes.com/dtds/podcast-1.0.dtd';

sub get-itunes-text($parent, Str $tag --> Str) is export {
    with $parent.elements(:TAG("itunes:$tag"))[0] -> $e {
        with $e.contents[0] -> $t {
            return $t.text // "";
        }
    }
    Str
}

sub get-itunes-duration($parent --> Str) is export {
    get-itunes-text($parent, "duration")
}

sub add-itunes-declaration(XML::Element $root --> Nil) is export {
    $root.attribs{'xmlns:itunes'} = NS
        unless $root.attribs{'xmlns:itunes'}.defined;
}

sub add-itunes-element(XML::Element $parent, Str $tag, Str $content --> Nil) is export {
    return unless $content.defined && $content.chars;
    $parent.append: XML::Element.new(:name("itunes:$tag"), :nodes([$content]));
}
