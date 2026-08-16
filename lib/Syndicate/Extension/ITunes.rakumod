use v6.d;
use XML;
use Syndicate::Extensions;
use Syndicate::Utils;

unit module Syndicate::Extension::ITunes:ver<0.0.3>:auth<zef:sasha>;

my constant NS = 'http://www.itunes.com/dtds/podcast-1.0.dtd';

register-ext(:namespace<itunes>, :namespace-uri('http://www.itunes.com/dtds/podcast-1.0.dtd'),
    parse => sub ($elem, %attrs) {
        # Single pass over the direct children, collecting author/summary/
        # duration together, instead of scanning the tree once per field.
        # Mirror the namespace resolution used by get-itunes-text.
        my (Str $author, Str $summary, Str $duration);
        for $elem.elements -> $e {
            my $name = $e.name;
            my $idx = $name.index(':');
            my $prefix = $idx.defined ?? $name.substr(0, $idx) !! '';
            my $local  = $idx.defined ?? $name.substr($idx + 1) !! $name;
            next unless $local eq 'author' | 'summary' | 'duration';
            my $match = False;
            with $e.nsPrefix(NS) -> $resolved {
                if $resolved.chars {
                    $match = $resolved eq $prefix;
                } elsif !$prefix.chars {
                    $match = True;
                }
            }
            # Lenient fallback: tolerate undeclared canonical-prefix elements.
            $match = True if !$match && $prefix eq 'itunes';
            next unless $match;
            my $text = decode-entities(element-text($e)).trim;
            $text = Str unless $text.defined && $text.chars;
            given $local {
                when 'author'   { $author   //= $text }
                when 'summary'  { $summary  //= $text }
                when 'duration' { $duration //= $text }
            }
        }
        %attrs<itunes-author>   = $author;
        %attrs<itunes-summary>  = $summary;
        %attrs<itunes-duration> = $duration;
    },
    generate => sub ($xml, $item) {
        with $item.?itunes-author  { add-itunes-element($xml, "author",   $_) }
        with $item.?itunes-summary { add-itunes-element($xml, "summary",  $_) }
        with $item.?itunes-duration { add-itunes-element($xml, "duration", $_) }
    }
);

sub get-itunes-text($parent, Str $tag --> Str) is export {
    # Namespace-aware: resolve the iTunes URI to whatever prefix is in scope
    # (canonical or otherwise), so <it:author> is matched like <itunes:author>.
    # Mirrors the namespace resolution used for content:encoded.
    my $e = elements-by-local-ns($parent, NS, $tag, "itunes")[0];
    return Str without $e;
    my $text = decode-entities(element-text($e)).trim;
    $text.defined && $text.chars ?? $text !! Str
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
