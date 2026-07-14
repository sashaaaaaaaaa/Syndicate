use v6.d;
use XML;
use Syndicate::Extensions;
use Syndicate::Utils;

my constant NS-DC is export = 'http://purl.org/dc/elements/1.1/';

unit module Syndicate::Extension::DublinCore:ver<0.0.1>:auth<zef:sasha>;

register-ext(:namespace<dc>, :namespace-uri(NS-DC),
    parse => sub ($elem, %attrs) {
        return unless $elem.elements.first({ .name.starts-with('dc:') });
        my $creator = get-dc-text($elem, "creator");
        if $creator.defined && $creator.chars {
            %attrs<author> = $creator;
            %attrs<has-dc-creator> = True;
        }
        with get-dc-text($elem, "date") -> $d {
            %attrs<updated> = $d if $d.defined && $d.chars;
        }
        my @subjects = get-dc-texts($elem, "subject");
        %attrs<dc-subjects> = @subjects if @subjects;
    },
    generate => sub ($xml, $item) {
        with $item.?has-dc-creator -> $v {
            if $v {
                add-dc-element($xml, "creator", ~$item.author) if $item.author.defined;
                with $item.updated -> $dt {
                    add-dc-element($xml, "date", ~$dt);
                }
            }
        }
        with $item.?dc-subjects -> @s {
            add-dc-element($xml, "subject", $_) for @s;
        }
    }
);

sub get-dc-text($parent, Str $tag --> Str) is export {
    with $parent.elements(:TAG("dc:$tag"))[0] -> $e {
        with $e.contents[0] -> $t {
            return decode-entities($t.?text // Str);
        }
    }
    Str
}

sub get-dc-texts($parent, Str $tag --> Array) is export {
    my @values;
    for $parent.elements(:TAG("dc:$tag")) -> $e {
        with $e.contents[0] -> $t {
            @values.push: decode-entities($t.text // "");
        }
    }
    @values
}

sub add-dc-declaration(XML::Element $root --> Nil) is export {
    $root.attribs{'xmlns:dc'} = NS-DC
        unless $root.attribs{'xmlns:dc'}.defined;
}

sub add-dc-element(XML::Element $parent, Str $tag, Str $content --> Nil) is export {
    return unless $content.defined && $content.chars;
    $parent.append: XML::Element.new(:name("dc:$tag"), :nodes([encode-entities($content)]));
}

=begin pod

=head1 NAME

Syndicate::Extension::DublinCore - Dublin Core metadata extension

=head1 DESCRIPTION

Automatically registers with L<C<Syndicate::Extensions>|rakudoc:Syndicate::Extensions>
to parse and generate C<dc:creator>, C<dc:date>, and C<dc:subject> elements
in RSS items.

Simply C<use> this module to activate:

=begin code :lang<raku>
use Syndicate::Extension::DublinCore;
=end code

=head1 EXPORTED SUBS

=item C<get-dc-text($parent, $tag)> - Get dc:* text content
=item C<get-dc-texts($parent, $tag)> - Get all dc:* text values as array
=item C<add-dc-declaration(XML::Element)> - Add namespace declaration
=item C<add-dc-element($parent, $tag, $content)> - Add dc:* element

=end pod
