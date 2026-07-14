use v6.d;
use XML;
use Syndicate::RSS::Item::Common;
use DateTime::Format::RFC2822;
my constant $RFC2822 = DateTime::Format::RFC2822.new;
use Syndicate::Utils;
use Syndicate::Extensions;
use Syndicate::Stats;
use Syndicate::Extension::DublinCore;

unit class Syndicate::RSS::V1_0::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::RSS::Item::Common;

has Str $.about;
has @.dc-subjects of Str;

method !item-type-name { "RSS 1.0 item" }

method from-xml(XML::Element $item-elem, :$active?) {
    my $about   = $item-elem.attribs{'rdf:about'} // $item-elem.attribs<about> // Str;
    my $title   = get-text-optional($item-elem, "title");
    my $link    = get-text-optional($item-elem, "link");
    my $desc    = get-text-optional($item-elem, "description");
    my $encoded = get-text-optional($item-elem, "content:encoded")
    // get-text-by-ns($item-elem, "encoded", 'http://purl.org/rss/1.0/modules/content/');

    my $author  = get-text-optional($item-elem, "author");
    my ($guid, $guid-is-permalink) = self!parse-guid($item-elem);
    my @categories = parse-categories($item-elem);
    my $comment = get-text-optional($item-elem, "comments");
    my %enclosure = self!parse-enclosure($item-elem);
    my $source  = get-text-optional($item-elem, "source");

    my %extra;
    my $act = $active // set-active(active-extensions, $item-elem);
    run-parsers($item-elem, %extra, :active($act));
    $author = $author.defined && $author.chars ?? $author !! %extra<author> // Str;

    my $updated = %extra<updated>:exists
        ?? parse-date-optional(%extra<updated>)
        !! Nil;
    my @dc-subjects = @(%extra<dc-subjects> // []);

    my @media-contents    = @(%extra<media-contents>    // []);
    my @media-thumbnails  = @(%extra<media-thumbnails>  // []);
    my @media-groups      = @(%extra<media-groups>      // []);
    my $media-title       = %extra<media-title>         // Str;
    my $media-description = %extra<media-description>   // Str;

    my $content = $encoded.defined && $encoded.chars ?? $encoded !! Str;
    my $item-id = $about // $link // Str;
    my %bless = :$about, :$title, :$link, :summary($desc),
                :$author,
                :id($item-id),
                :$content,
                :has-dc-creator(%extra<has-dc-creator> // False),
                :$guid, :$guid-is-permalink,
                :comments($comment), :enclosure(%enclosure), :source($source);
    %bless<updated> = $updated if $updated ~~ DateTime;
    my $item = self.bless(|%bless, :@categories, :dc-subjects(@dc-subjects),
        :@media-contents, :@media-thumbnails, :@media-groups, :$media-title, :$media-description,
        :itunes-author(%extra<itunes-author> // Str),
        :itunes-summary(%extra<itunes-summary> // Str),
        :itunes-duration(%extra<itunes-duration> // Str),
        :active-ext($act));
    Syndicate::Stats.record-item;
    $item
}

method XML {
    my $xml = XML::Element.new(:name<item>);
    $xml.attribs{'rdf:about'} = $.about if $.about.defined;
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

    if $.content.defined && $.content.chars {
        $xml.append: XML::Element.new(:name<content:encoded>, :nodes([encode-entities($.content)]));
    }

    run-generators($xml, self, :active($!active-ext));
    $xml
}

method namespace-flags() {
    (
        $!has-dc-creator || $!updated.defined || ?(@!dc-subjects),
        ?(@!media-contents) || ?(@!media-thumbnails) || ?(@!media-groups) || $!media-title.defined || $!media-description.defined,
        $!itunes-author.defined || $!itunes-summary.defined || $!itunes-duration.defined,
        ?($!content.defined && $!content.chars),
    )
}

=begin pod

=head1 NAME

Syndicate::RSS::V1_0::Item - RSS 1.0 (RDF) item

=head1 DESCRIPTION

An RSS 1.0 item. Does L<C<Syndicate::RSS::Item::Common>|rakudoc:Syndicate::RSS::Item::Common>.

=head1 ATTRIBUTES

=item C<$.about> - RDF about URL
=item C<@.dc-subjects> - Dublin Core subjects

=end pod
