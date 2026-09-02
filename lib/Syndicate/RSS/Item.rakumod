use v6.d;
use XML;
use Syndicate::RSS::Item::Common;
use Syndicate::RSS::Common;
use Syndicate::Utils;
use Syndicate::Extensions;
use Syndicate::Stats;

unit class Syndicate::RSS::Item:ver<0.0.5>:auth<zef:sasha> does Syndicate::RSS::Item::Common;

method from-xml(XML::Element $item-elem, :$active?) {
    # Index direct children once: per-field elements(:TAG<...>) calls each scan
    # linearly, making a parse O(fields x children). Reads below use the index.
    my @kids = $item-elem.elements;
    my %child;
    %child{$_.name}.push($_) for @kids;
    my sub idx-text(Str $tag --> Str) {
        my $e = %child{$tag}[0];
        return Str unless $e.defined;
        my $t = element-text($e).trim;
        $t.chars ?? decode-entities($t) !! Str
    }

    my $title   = idx-text("title");
    my $link    = idx-text("link");
    my $desc    = idx-text("description");
    my ($encoded, $content-is-markup);
    with %child{'content:encoded'}[0]
        // elements-by-local-ns($item-elem, NS-CONTENT, "encoded", "content")[0]
    {
        ($encoded, $content-is-markup) = content-and-markup($_);
    }
    my $author  = idx-text("author");
    my @categories = parse-categories($item-elem);
    my $comment = idx-text("comments");
    my $pubdate = parse-date(:optional, idx-text("pubDate"));
    my $source  = idx-text("source");

    my ($guid, $guid-is-permalink) = self!parse-guid($item-elem);
    my %enclosure = self!parse-enclosure($item-elem);

    my %extra;
    my $act = $active // set-active(active-extensions, $item-elem);
    run-parsers($item-elem, %extra, :active($act));
    # %extra keys from extensions: author, has-dc-creator, media-contents,
    #   media-thumbnails, media-title, media-description,
    #   itunes-author, itunes-summary, itunes-duration
    # Prefer explicit <author> over dc:creator to match RSS 2.0 element priority
    $author = $author.defined && $author.chars ?? $author !! %extra<author> // Str;
    # The original dc:creator/dc:subject values are preserved so they round-trip
    # even when an explicit <author> overrides the author slot.
    my @dc-creators = @(%extra<dc-creators> // []);
    my @dc-subjects = @(%extra<dc-subjects> // []);
    my $dc-updated = %extra<updated>:exists
        ?? parse-date(:optional, %extra<updated>)
        !! Nil;

    my @media-contents    = @(%extra<media-contents>    // []);
    my @media-thumbnails  = @(%extra<media-thumbnails>  // []);
    my @media-groups      = @(%extra<media-groups>      // []);
    my $media-title       = %extra<media-title>         // Str;
    my $media-description = %extra<media-description>   // Str;

    my $content = $encoded.defined && $encoded.chars ?? $encoded !! Str;
    my $item-id = $guid // $link // Str;
    my %bless = :$title, :$link, :summary($desc),
        :$author,
        :id($item-id), :$guid,
        :$content,
        :content-is-markup($content-is-markup // False),
        :has-dc-creator(%extra<has-dc-creator> // False),
        :has-dc-date(%extra<has-dc-date> // False),
        :comments($comment),
        :enclosure(%enclosure), :source($source), :$guid-is-permalink,
        :media-title($media-title), :media-description($media-description),
        :itunes-author(%extra<itunes-author> // Str),
        :itunes-summary(%extra<itunes-summary> // Str),
        :itunes-duration(%extra<itunes-duration> // Str);
    %bless<updated> = $pubdate if $pubdate ~~ DateTime;
    %bless<updated> //= $dc-updated if $dc-updated ~~ DateTime;
    my $item = self.bless(|%bless, :@categories, :@dc-creators, :@dc-subjects,
        :@media-contents, :@media-thumbnails, :@media-groups, :active-ext($act));
    Syndicate::Stats.record-item;
    $item
}

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

An RSS 2.0 item. Does L<C<Syndicate::RSS::Item::Common>|rakudoc:Syndicate::RSS::Item::Common>.

=head1 ATTRIBUTES

=item C<$.title>, C<$.link>, C<$.summary>, C<$.author>, C<$.updated> - from Item role
=item C<$.id>, C<$.content> - from Item role
=item C<$.guid> - Globally unique identifier (falls back to link)
=item C<$.guid-is-permalink> - Whether guid is a permalink (default: True)
=item C<@.categories> - Item categories
=item C<$.comments> - Comments URL
=item C<%.enclosure> - Enclosure hash (url, length, type)
=item C<$.source> - Source feed URL
=item C<@.media-contents> - Media RSS content entries
=item C<@.media-thumbnails> - Media RSS thumbnails
=item C<@.media-groups> - Media RSS groups
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
