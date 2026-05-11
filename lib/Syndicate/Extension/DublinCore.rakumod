use v6.d;
use XML;
use Syndicate::Extensions;

unit module Syndicate::Extension::DublinCore:ver<0.0.1>:auth<zef:sasha>;

register-ext(
    parse => sub ($elem, %attrs) {
        if !%attrs<author>.defined || !%attrs<author>.chars {
            my $creator = get-dc-text($elem, "creator");
            %attrs<author> = $creator if $creator.defined && $creator.chars;
        }
    },
    generate => sub ($xml, $item) {
        add-dc-element($xml, "creator", $item.author) if $item.author.defined;
    }
);

sub get-dc-text($parent, Str $tag --> Str) is export {
    with $parent.elements(:TAG("dc:$tag"))[0] -> $e {
        with $e.contents[0] -> $t {
            return $t.text // "";
        }
    }
    Str
}

sub get-dc-texts($parent, Str $tag --> Array) is export {
    my @values;
    for $parent.elements(:TAG("dc:$tag")) -> $e {
        with $e.contents[0] -> $t {
            @values.push: $t.text // "";
        }
    }
    @values
}

sub add-dc-declaration(XML::Element $root --> Nil) is export {
    $root.attribs{'xmlns:dc'} = 'http://purl.org/dc/elements/1.1/'
        unless $root.attribs{'xmlns:dc'}.defined;
}

sub add-dc-element(XML::Element $parent, Str $tag, Str $content --> Nil) is export {
    return unless $content.defined && $content.chars;
    $parent.append: XML::Element.new(:name("dc:$tag"), :nodes([$content]));
}
