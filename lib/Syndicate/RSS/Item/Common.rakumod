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
has Str $.about;
has @.dc-subjects of Str;
has @.media-contents of Hash;
has @.media-thumbnails of Hash;
has @.media-groups of Hash;
has Str $.media-title;
has Str $.media-description;
has Str $.itunes-author;
has Str $.itunes-summary;
has Str $.itunes-duration;
has Set $.active-ext;
has Bool $!is-rdf is built = False;
has Bool $!is-v091 is built = False;
has Str $!cached-str;
has Lock $!cache-lock = Lock.new;
has XML::Element $!cached-xml;
has Lock $!xml-lock = Lock.new;

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
    with-error-recording { self.from-xml($doc.root) }
}

multi method new(XML::Element $xml-elem) {
    with-error-recording { self.from-xml($xml-elem) }
}

method !parse-guid(XML::Element $item-elem) {
    my $guid-elem = $item-elem.elements(:TAG<guid>)[0];
    return (Str, True) unless $guid-elem;
    my $guid = decode-entities(element-text($guid-elem));
    $guid = Str unless $guid.chars;
    my $raw = ($guid-elem.attribs<isPermaLink> // "true").lc;
    my $is-permalink = $raw eq "true" || $raw eq "1";
    ($guid, $is-permalink)
}

method !parse-enclosure(XML::Element $item-elem) {
    my %enclosure;
    with $item-elem.elements(:TAG<enclosure>)[0] {
        %enclosure<url>    = decode-entities(.attribs<url>    // Str);
        %enclosure<length> = decode-entities(.attribs<length> // Str);
        %enclosure<type>   = decode-entities(.attribs<type>   // Str);
    }
    %enclosure
}

method Str {
    $!cached-str // $!cache-lock.protect: { $!cached-str //= ~self.XML }
}

method XML {
    return $!cached-xml if $!cached-xml.defined;
    $!xml-lock.protect: {
        return $!cached-xml if $!cached-xml.defined;
        my $xml = XML::Element.new(:name<item>);
        add-attrib($xml, 'rdf:about', $.about) if $!is-rdf && $.about.defined;
        add-element($xml, "title", $.title);
        add-element($xml, "link",  $.link);
        unless $!is-v091 {
            if $.guid.defined && $.guid.chars {
                my $guid-elem = XML::Element.new(:name<guid>, :nodes([encode-entities($.guid)]));
                $guid-elem.attribs<isPermaLink> = $.guid-is-permalink ?? "true" !! "false";
                $xml.append: $guid-elem;
            }
        }
        add-element($xml, "description", $.summary);
        if !$!is-v091 && $.content.defined && $.content.chars {
            $xml.append: XML::Element.new(:name<content:encoded>, :nodes([encode-entities($.content)]));
        }
        unless $!is-v091 {
            if $.updated.defined {
                if $!is-rdf {
                    # The DublinCore extension emits <dc:date> when
                    # has-dc-creator is set, so only emit it here when the
                    # extension will not (avoids duplicate <dc:date>).
                    unless $!has-dc-creator {
                        $xml.append: XML::Element.new(:name<dc:date>, :nodes([$.updated.Str]));
                    }
                } else {
                    $xml.append: XML::Element.new(:name<pubDate>, :nodes([RFC2822-FORMAT.to-string($.updated)]));
                }
            }
            add-element($xml, "author",   $.author);
            add-element($xml, "category", $_) for @.categories;
            add-element($xml, "comments", $.comments);
            if %.enclosure<url>.defined && %.enclosure<url>.chars {
                my $enc = XML::Element.new(:name<enclosure>);
                $enc.attribs<url> = encode-entities(%.enclosure<url>);
                $enc.attribs<length> = encode-entities(%.enclosure<length>) if %.enclosure<length>.defined && %.enclosure<length>.chars;
                $enc.attribs<type>   = encode-entities(%.enclosure<type>)   if %.enclosure<type>.defined   && %.enclosure<type>.chars;
                $xml.append: $enc;
            }
            add-element($xml, "source", $.source);
        }

        run-generators($xml, self, :active($!active-ext));

        $!cached-xml = $xml;
        $xml
    }
}

method namespace-flags() {
    %(
        :dc($!has-dc-creator && !$!is-v091),
        :media(?(@!media-contents) || ?(@!media-thumbnails) || ?(@!media-groups) || $!media-title.defined || $!media-description.defined),
        :itunes($!itunes-author.defined || $!itunes-summary.defined || $!itunes-duration.defined),
        :content(!$!is-v091 && ?($.content.defined && $.content.chars)),
    )
}

method is-v091(--> Bool) { $!is-v091 }

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
