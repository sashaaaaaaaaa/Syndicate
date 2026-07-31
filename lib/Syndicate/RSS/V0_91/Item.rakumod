use v6.d;
use XML;
use Syndicate::RSS::Item::Common;
use Syndicate::Utils;
use Syndicate::Extensions;
use Syndicate::Stats;

unit class Syndicate::RSS::V0_91::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::RSS::Item::Common;

method !item-type-name { "RSS 0.91 item" }

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
    my $act = $active // set-active(active-extensions, $item-elem);
    run-parsers($item-elem, %extra, :active($act));
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
        :itunes-duration(%extra<itunes-duration> // Str),
        :active-ext($act), :is-v091);
    Syndicate::Stats.record-item;
    $item
}

=begin pod

=head1 NAME

Syndicate::RSS::V0_91::Item - RSS 0.91 item

=head1 DESCRIPTION

An RSS 0.91 item. Does L<C<Syndicate::RSS::Item::Common>|rakudoc:Syndicate::RSS::Item::Common>.
Supports title, link, and description, plus guid, categories, comments,
enclosure, and source. Dublin Core metadata is parsed into C<author> and
C<updated> but is not re-emitted — the RSS 0.91 DTD has no Dublin Core
elements. Media RSS and iTunes metadata are parsed and roundtripped when
present, but C<content:encoded> is never emitted — RSS 0.91 has no content
module element.

=end pod
