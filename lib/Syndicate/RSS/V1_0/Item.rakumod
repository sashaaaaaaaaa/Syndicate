use v6.d;
use XML;
use Syndicate::RSS::Item::Common;
use Syndicate::Utils;
use Syndicate::Extensions;
use Syndicate::Stats;
use Syndicate::Extension::DublinCore;

unit class Syndicate::RSS::V1_0::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::RSS::Item::Common;

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
        :active-ext($act), :is-rdf);
    Syndicate::Stats.record-item;
    $item
}

method namespace-flags() {
    %(
        :dc($!has-dc-creator || $!updated.defined || ?(@!dc-subjects)),
        :media(?(@!media-contents) || ?(@!media-thumbnails) || ?(@!media-groups) || $!media-title.defined || $!media-description.defined),
        :itunes($!itunes-author.defined || $!itunes-summary.defined || $!itunes-duration.defined),
        :content(?($.content.defined && $.content.chars)),
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
