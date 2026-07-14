use v6.d;
use XML;
use Syndicate::Item;
use DateTime::Format::RFC2822;
my constant $RFC2822 = DateTime::Format::RFC2822.new;
use Syndicate::Utils;
use Syndicate::Extensions;
use Syndicate::Stats;

unit class Syndicate::RSS::V0_91::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

has Bool $.has-dc-creator;
has Str $.guid;
has Bool $.guid-is-permalink = True;
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
has Str $!cached-str;
has Lock $!cache-lock = Lock.new;

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    unless $doc {
        Syndicate::Stats.record-error;
        die "Invalid RSS 0.91 item XML: $!";
    }
    unless $doc.root.name eq "item" {
        Syndicate::Stats.record-error;
        die "Not an RSS 0.91 item element";
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

method from-xml(XML::Element $item-elem, :$active?) {
    my $title = get-text-optional($item-elem, "title");
    my $link  = get-text-optional($item-elem, "link");
    my $desc  = get-text-optional($item-elem, "description");

    my ($guid, $guid-is-permalink) = self!parse-guid($item-elem);
    my @categories = parse-categories($item-elem);
    my $comment = get-text-optional($item-elem, "comments");
    my %enclosure = self!parse-enclosure($item-elem);
    my $source  = get-text-optional($item-elem, "source");

    my %extra;
    run-parsers($item-elem, %extra, :$active);
    my $author = %extra<author> // Str;

    my $updated = %extra<updated>:exists
        ?? parse-date-optional(%extra<updated>)
        !! Nil;

    my @media-contents    = @(%extra<media-contents>    // []);
    my @media-thumbnails  = @(%extra<media-thumbnails>  // []);
    my @media-groups      = @(%extra<media-groups>      // []);
    my $media-title       = %extra<media-title>         // Str;
    my $media-description = %extra<media-description>   // Str;

    my %bless = :$title, :$link, :summary($desc), :$author, :id($guid // $link // Str),
        :has-dc-creator(%extra<has-dc-creator> // False),
        :$guid, :$guid-is-permalink,
        :comments($comment), :enclosure(%enclosure), :source($source);
    %bless<updated> = $updated if $updated ~~ DateTime;
    my $item = self.bless(|%bless, :@categories,
        :@media-contents, :@media-thumbnails, :@media-groups, :$media-title, :$media-description,
        :itunes-author(%extra<itunes-author> // Str),
        :itunes-summary(%extra<itunes-summary> // Str),
        :itunes-duration(%extra<itunes-duration> // Str));
    Syndicate::Stats.record-item;
    $item
}

method XML {
    my $xml = XML::Element.new(:name<item>);
    add-element($xml, "title",       $.title);
    add-element($xml, "link",        $.link);
    if $.guid.defined && $.guid.chars {
        my $guid-elem = XML::Element.new(:name<guid>, :nodes([encode-entities($.guid)]));
        $guid-elem.attribs<isPermaLink> = $.guid-is-permalink ?? "true" !! "false";
        $xml.append: $guid-elem;
    }
    add-element($xml, "description", $.summary);
    if $.updated.defined {
        $xml.append: XML::Element.new(:name<pubDate>, :nodes([$RFC2822.to-string($.updated)]));
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
    run-generators($xml, self);
    $xml
}

method Str {
    $!cache-lock.protect: { $!cached-str //= ~self.XML }
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

method namespace-flags() {
    (
        $!has-dc-creator,
        ?(@!media-contents) || ?(@!media-thumbnails) || ?(@!media-groups) || $!media-title.defined || $!media-description.defined,
        $!itunes-author.defined || $!itunes-summary.defined || $!itunes-duration.defined,
        False,  # V0_91 does not support content:encoded
    )
}

=begin pod

=head1 NAME

Syndicate::RSS::V0_91::Item - RSS 0.91 item

=head1 DESCRIPTION

An RSS 0.91 item. Does L<C<Syndicate::Item>|rakudoc:Syndicate::Item>.
Only supports title, link, and description — no metadata fields.

=end pod
