use v6.d;
use XML;
use Syndicate::Extensions;
use Syndicate::Utils;

my constant NS-DC is export = 'http://purl.org/dc/elements/1.1/';

unit module Syndicate::Extension::DublinCore:ver<0.0.1>:auth<zef:sasha>;

register-ext(:namespace<dc>, :namespace-uri(NS-DC),
    parse => sub ($elem, %attrs) {
        my @creators = get-dc-texts($elem, "creator");
        if @creators {
            %attrs<author> = @creators[0];
            %attrs<has-dc-creator> = True;
            %attrs<dc-creators> = @creators;
        }
        with get-dc-text($elem, "date") -> $d {
            %attrs<updated> = $d if $d.defined && $d.chars;
            %attrs<has-dc-date> = True;
        }
        my @subjects = get-dc-texts($elem, "subject");
        %attrs<dc-subjects> = @subjects if @subjects;
    },
    generate => sub ($xml, $item) {
        # RSS 0.91 has no Dublin Core in its DTD; skip the namespace entirely.
        return if $item.?is-v091;
        my $emit-date = $item.?has-dc-creator || $item.?has-dc-date;
        with $item.?has-dc-creator -> $v {
            if $v {
                # Prefer the original dc:creator value(s) so the element
                # round-trips exactly; fall back to the author for items
                # built with only the flag (Builder path).
                my @creators = @($item.?dc-creators // []);
                if @creators {
                    add-dc-element($xml, "creator", $_) for @creators;
                } elsif $item.author.defined {
                    add-dc-element($xml, "creator", ~$item.author);
                }
            }
        }
        # A parsed dc:date round-trips as <dc:date> (in addition to the
        # normalized pubDate/updated), while Builder items that never had
        # one keep emitting only the native timestamp.
        if $emit-date {
            with $item.updated -> $dt {
                add-dc-element($xml, "date", ~$dt);
            }
        }
        with $item.?dc-subjects -> @s {
            add-dc-element($xml, "subject", $_) for @s;
        }
    }
);

sub get-dc-text($parent, Str $tag --> Str) is export {
    my $e = elements-by-local-ns($parent, NS-DC, $tag, "dc")[0];
    return Str without $e;
    my $text = element-text($e).trim;
    $text.chars ?? decode-entities($text) !! Str
}

sub get-dc-texts($parent, Str $tag --> Array) is export {
    my @values;
    for elements-by-local-ns($parent, NS-DC, $tag, "dc") -> $e {
        my $text = element-text($e).trim;
        @values.push: decode-entities($text) if $text.chars;
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
