use v6.d;
use XML;
use Syndicate::Item;
use DateTime::Format::RFC2822;
my constant $RFC2822 = DateTime::Format::RFC2822.new;
use Syndicate::Utils;
use Syndicate::Extensions;
use Syndicate::Stats;

unit class Syndicate::RSS::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

has Str $.guid;
has Bool $.guid-is-permalink = True;
has Bool $.has-dc-creator;
has @.categories of Str;
has Str $.comments;
has %.enclosure of Str;
has Str $.source;
has @.media-contents of Hash;
has @.media-thumbnails of Hash;
has Str $.media-title;
has Str $.media-description;
has Str $.itunes-author;
has Str $.itunes-summary;
has Str $.itunes-duration;
has Str $!cached-str;
has Lock $!cache-lock = Lock.new;

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    die "Invalid RSS item XML: $!" unless $doc;
    die "Not an RSS item element" unless $doc.root.name eq "item";
    my $item = self.from-xml($doc.root);
    CATCH { Syndicate::Stats.record-error; .rethrow }
    $item
}

multi method new(XML::Element $xml-elem) {
    my $item = self.from-xml($xml-elem);
    CATCH { Syndicate::Stats.record-error; .rethrow }
    $item
}

multi method from-xml(XML::Element $item-elem) {
    my $title   = get-text-optional($item-elem, "title");
    my $link    = get-text-optional($item-elem, "link");
    my $desc    = get-text-optional($item-elem, "description");
    my $encoded = get-text-optional($item-elem, "content:encoded");
    my $author  = get-text-optional($item-elem, "author");
    my @categories = parse-categories($item-elem);
    my $comment = get-text-optional($item-elem, "comments");
    my $pubdate = parse-date-optional(get-text-optional($item-elem, "pubDate"));
    my $source  = get-text-optional($item-elem, "source");

    my $guid-elem = $item-elem.elements(:TAG<guid>)[0];
    my $guid = Str;
    my $guid-is-permalink = True;
    with $guid-elem {
        $guid = .contents[0].?text // Str;
        $guid-is-permalink = (.attribs<isPermaLink> // "true") eq "true";
    }

    my %enclosure;
    with $item-elem.elements(:TAG<enclosure>)[0] {
        %enclosure<url>    = .attribs<url>    // Str;
        %enclosure<length> = .attribs<length> // Str;
        %enclosure<type>   = .attribs<type>   // Str;
    }

    my %extra;
    %extra<author> = $author if $author.defined && $author.chars;
    run-parsers($item-elem, %extra);
    # Prefer explicit <author> over dc:creator to match RSS 2.0 element priority
    $author = $author.defined && $author.chars ?? $author !! %extra<author> // Str;
    # dc:subject is intentionally not stored here — only V1_0 items track @.dc-subjects

    my @media-contents    = @(%extra<media-contents>    // []);
    my @media-thumbnails  = @(%extra<media-thumbnails>  // []);
    my $media-title       = %extra<media-title>         // Str;
    my $media-description = %extra<media-description>   // Str;

    my $content = $encoded.defined && $encoded.chars ?? $encoded !! Str;
    my $item-id = $guid // $link // Str;
    my %bless = :$title, :$link, :summary($desc),
        :$author,
        :id($item-id),
        :$content,
        :has-dc-creator(%extra<has-dc-creator> // False),
        :comments($comment),
        :enclosure(%enclosure), :source($source),
        :media-title($media-title), :media-description($media-description),
        :itunes-author(%extra<itunes-author> // Str),
        :itunes-summary(%extra<itunes-summary> // Str),
        :itunes-duration(%extra<itunes-duration> // Str);
    %bless<updated> = $pubdate if $pubdate ~~ DateTime;
    my $item = self.bless(|%bless, :@categories, :@media-contents, :@media-thumbnails);
    Syndicate::Stats.record-item;
    $item
}

method XML {
    my $xml = XML::Element.new(:name<item>);
    add-element($xml, "title", $.title);
    add-element($xml, "link",  $.link);
    if $.guid.defined {
        my $guid-elem = XML::Element.new(:name<guid>, :nodes([encode-entities($.guid)]));
        $guid-elem.attribs<isPermaLink> = $.guid-is-permalink ?? "true" !! "false";
        $xml.append: $guid-elem;
    }
    add-element($xml, "description", $.summary);
    if $.content.defined && $.content.chars {
        $xml.append: XML::Element.new(:name<content:encoded>, :nodes([encode-entities($.content)]));
    }
    if $.updated.defined {
        $xml.append: XML::Element.new(:name<pubDate>, :nodes([$RFC2822.to-string($.updated)]));
    }
    add-element($xml, "author",   $.author);
    add-element($xml, "category", $_) for @.categories;
    add-element($xml, "comments", $.comments);
    if %.enclosure<url>.defined && %.enclosure<url>.chars {
        my $enc = XML::Element.new(:name<enclosure>);
        $enc.attribs<url> = encode-entities(%.enclosure<url>);
        $enc.attribs<length> = %.enclosure<length> if %.enclosure<length>.defined && %.enclosure<length>.chars;
        $enc.attribs<type>   = %.enclosure<type>   if %.enclosure<type>.defined   && %.enclosure<type>.chars;
        $xml.append: $enc;
    }
    add-element($xml, "source", $.source);

    run-generators($xml, self);

    return $xml;
}

method Str { $!cache-lock.protect: { $!cached-str //= ~self.XML } }

=begin pod

=head1 NAME

Syndicate::RSS::Item - RSS 2.0 item

=head1 SYNOPSIS

=begin code :lang<raku>
my $item = Syndicate::RSS::Item.new(
    :title("Article"),
    :link("https://example.com/1"),
    :summary("Description"),
    :guid("https://example.com/1"),
    :author("author@example.com"),
    :updated(DateTime.now),
);
say ~$item;  # XML output
=end code

=head1 DESCRIPTION

An RSS 2.0 item. Does L<C<Syndicate::Item>|rakudoc:Syndicate::Item>.

=head1 ATTRIBUTES

=item C<$.title>, C<$.link>, C<$.summary>, C<$.author>, C<$.updated> - from Item role
=item C<$.id>, C<$.content> - from Item role
=item C<$.guid> - Globally unique identifier (falls back to link)
=item C<$.guid-is-permalink> - Whether guid is a permalink (default: True)
=item C<$.category> - Item category
=item C<$.comments> - Comments URL
=item C<%.enclosure> - Enclosure hash (url, length, type)
=item C<$.source> - Source feed URL
=item C<@.media-contents> - Media RSS content entries
=item C<@.media-thumbnails> - Media RSS thumbnails
=item C<$.media-title> - Media RSS title
=item C<$.media-description> - Media RSS description
=item C<$.itunes-author> - iTunes author
=item C<$.itunes-summary> - iTunes summary
=item C<$.itunes-duration> - iTunes duration (HH:MM:SS)

=head1 METHODS

=item C<new(Str $xml)> - Parse from XML element string
=item C<new(XML::Element)> - Parse from XML::Element
=item C<from-xml(XML::Element)> - Parse from XML element
=item C<XML> - Returns L<C<XML::Element>|rakudoc:XML::Element>
=item C<Str> - Returns XML string

=end pod
