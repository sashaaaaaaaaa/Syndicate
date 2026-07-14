use v6.d;
use XML;
use Syndicate::Item;
use Syndicate::Utils;
use Syndicate::Extensions;
use Syndicate::Stats;

unit role Syndicate::RSS::Item::Common:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

has Str $.guid;
has Bool $.guid-is-permalink = True;
has Bool $.has-dc-creator;
has @.categories of Str;
has Str $.comments;
has %.enclosure of Str;
has Str $.source;
has @.media-contents of Hash;
has @.media-thumbnails of Hash;
has @.media-groups of Hash;
has Str $.media-title;
has Str $.media-description;
has Str $.itunes-author;
has Str $.itunes-summary;
has Str $.itunes-duration;
has Set $.active-ext;
has Str $!cached-str;
has Lock $!cache-lock = Lock.new;

method !item-type-name { "RSS item" }

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    unless $doc {
        Syndicate::Stats.record-error;
        die "Invalid {self!item-type-name} XML: $!";
    }
    unless $doc.root.name eq "item" {
        Syndicate::Stats.record-error;
        die "Not an {self!item-type-name} element";
    }
    my $item;
    {
        $item = self.from-xml($doc.root);
        CATCH {
            when X::Control { .rethrow }
            default { Syndicate::Stats.record-error; .rethrow }
        }
    }
    $item
}

multi method new(XML::Element $xml-elem) {
    my $item = self.from-xml($xml-elem);
    CATCH {
        when X::Control { .rethrow }
        default { Syndicate::Stats.record-error; .rethrow }
    }
    $item
}

method !parse-guid(XML::Element $item-elem) {
    my $guid-elem = $item-elem.elements(:TAG<guid>)[0];
    return (Str, True) unless $guid-elem;
    my $guid = decode-entities($guid-elem.contents[0].?text // Str);
    my $is-permalink = ($guid-elem.attribs<isPermaLink> // "true") eq "true";
    ($guid, $is-permalink)
}

method !parse-enclosure(XML::Element $item-elem) {
    my %enclosure;
    with $item-elem.elements(:TAG<enclosure>)[0] {
        %enclosure<url>    = .attribs<url>    // Str;
        %enclosure<length> = .attribs<length> // Str;
        %enclosure<type>   = .attribs<type>   // Str;
    }
    %enclosure
}

method Str {
    $!cache-lock.protect: { $!cached-str //= ~self.XML }
}

=begin pod

=head1 NAME

Syndicate::RSS::Item::Common - Shared role for RSS Item classes

=head1 DESCRIPTION

Provides shared attributes and methods for L<C<Syndicate::RSS::Item>|rakudoc:Syndicate::RSS::Item>,
L<C<Syndicate::RSS::V0_91::Item>|rakudoc:Syndicate::RSS::V0_91::Item>,
and L<C<Syndicate::RSS::V1_0::Item>|rakudoc:Syndicate::RSS::V1_0::Item>.

Eliminates duplication of guid/enclosure parsing, string caching, and
common attribute declarations.

=end pod
