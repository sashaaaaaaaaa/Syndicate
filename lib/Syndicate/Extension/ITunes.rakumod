use v6.d;
use XML;
use Syndicate::Extensions;
use Syndicate::Utils;

unit module Syndicate::Extension::ITunes:ver<0.0.1>:auth<zef:sasha>;

register-ext(:namespace<itunes>,
    parse => sub ($elem, %attrs) {
        return unless $elem.elements.first({ .name.starts-with('itunes:') });
        %attrs<itunes-author>   = get-itunes-text($elem, "author");
        %attrs<itunes-summary>  = get-itunes-text($elem, "summary");
        %attrs<itunes-duration> = get-itunes-duration($elem);
    },
    generate => sub ($xml, $item) {
        with $item.?itunes-author  { add-itunes-element($xml, "author",   $_) }
        with $item.?itunes-summary { add-itunes-element($xml, "summary",  $_) }
        with $item.?itunes-duration { add-itunes-element($xml, "duration", $_) }
    }
);

my constant NS = 'http://www.itunes.com/dtds/podcast-1.0.dtd';

sub get-itunes-text($parent, Str $tag --> Str) is export {
    with $parent.elements(:TAG("itunes:$tag"))[0] -> $e {
        with $e.contents[0] -> $t {
            my $text = ($t.?text // "").trim;
            return $text.defined && $text.chars ?? decode-entities($text) !! Str;
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
    $parent.append: XML::Element.new(:name("itunes:$tag"), :nodes([encode-entities($content)]));
}

=begin pod

=head1 NAME

Syndicate::Extension::ITunes - iTunes podcast extension

=head1 DESCRIPTION

Automatically registers with L<C<Syndicate::Extensions>|rakudoc:Syndicate::Extensions>
to parse and generate C<itunes:author>, C<itunes:summary>, and C<itunes:duration>
elements in RSS items.

Simply C<use> this module to activate:

=begin code :lang<raku>
use Syndicate::Extension::ITunes;
=end code

=head1 EXPORTED SUBS

=item C<get-itunes-text($parent, $tag)> - Get itunes:* text
=item C<get-itunes-duration($parent)> - Get itunes:duration
=item C<add-itunes-declaration(XML::Element)> - Add namespace declaration
=item C<add-itunes-element($parent, $tag, $content)> - Add itunes:* element

=end pod
