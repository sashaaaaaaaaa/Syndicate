use v6.d;
use XML;
use Syndicate::RSS::Item::Common;
use Syndicate::RSS::Common;
use Syndicate::Utils;
use Syndicate::Extensions;
use Syndicate::Stats;
use Syndicate::Extension::DublinCore;

unit class Syndicate::RSS::V1_0::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::RSS::Item::Common;

method !item-type-name { "RSS 1.0 item" }

# Direct construction (new(:title, ...)) must produce RSS 1.0-flavored
# output (dc:date/dc:creator, rdf:about) rather than silently defaulting
# to RSS 2.0 output via the shared role's is-rdf = False default.
submethod TWEAK {
    $!is-rdf = True;
}

method from-xml(XML::Element $item-elem, :$active?) {
    my $about   = decode-entities($item-elem.attribs{'rdf:about'} // $item-elem.attribs<about> // Str);
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
    my ($guid, $guid-is-permalink) = self!parse-guid($item-elem);
    my @categories = parse-categories($item-elem);
    my $comment = idx-text("comments");
    my %enclosure = self!parse-enclosure($item-elem);
    my $source  = idx-text("source");

    my %extra;
    my $act = $active // set-active(active-extensions, $item-elem);
    run-parsers($item-elem, %extra, :active($act));
    $author = $author.defined && $author.chars ?? $author !! %extra<author> // Str;

    my $updated = %extra<updated>:exists
        ?? parse-date-optional(%extra<updated>)
        !! Nil;
    my @dc-subjects = @(%extra<dc-subjects> // []);
    my @dc-creators = @(%extra<dc-creators> // []);

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
                :content-is-markup($content-is-markup // False),
                :has-dc-creator(%extra<has-dc-creator> // False),
                :has-dc-date(%extra<has-dc-date> // False),
                :$guid, :$guid-is-permalink,
                :comments($comment), :enclosure(%enclosure), :source($source);
    %bless<updated> = $updated if $updated ~~ DateTime;
    my $item = self.bless(|%bless, :@categories, :@dc-creators, :dc-subjects(@dc-subjects),
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
        :dc($!has-dc-creator || $!has-dc-date || $!updated.defined || ?(@!dc-creators) || ?(@!dc-subjects)),
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
