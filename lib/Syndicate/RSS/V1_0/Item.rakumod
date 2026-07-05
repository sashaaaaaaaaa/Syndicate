use v6.d;
use XML;
use Syndicate::Item;
use Syndicate::Utils;
use Syndicate::Extensions;
use Syndicate::Stats;
use Syndicate::Extension::DublinCore;

unit class Syndicate::RSS::V1_0::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

has Str $.about;
has Bool $.has-dc-creator;
has @.dc-subjects of Str;
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
    die "Invalid RSS 1.0 item XML: $!" unless $doc;
    self.from-xml($doc.root)
}

multi method new(XML::Element $xml-elem) {
    self.from-xml($xml-elem)
}

multi method from-xml(XML::Element $item-elem) {
    my $about   = $item-elem.attribs{'rdf:about'} // $item-elem.attribs<about> // Str;
    my $title   = get-text-optional($item-elem, "title");
    my $link    = get-text-optional($item-elem, "link");
    my $desc    = get-text-optional($item-elem, "description");
    my $encoded = get-text-optional($item-elem, "content:encoded");

    my %extra;
    run-parsers($item-elem, %extra);
    my $author = %extra<author> // Str;

    my $updated = %extra<updated>:exists
        ?? parse-date-optional(%extra<updated>)
        !! Nil;
    my @dc-subjects = @(%extra<dc-subjects> // []);

    my @media-contents    = @(%extra<media-contents>    // []);
    my @media-thumbnails  = @(%extra<media-thumbnails>  // []);
    my $media-title       = %extra<media-title>         // Str;
    my $media-description = %extra<media-description>   // Str;

    my $content = $encoded.defined && $encoded.chars ?? $encoded !! $desc // Str;
    my $item-id = $about // $link // Str;
    my %bless = :$about, :$title, :$link, :summary($desc),
                :$author,
                :id($item-id),
                :$content,
                :has-dc-creator(%extra<has-dc-creator> // False);
    %bless<updated> = $updated if $updated ~~ DateTime;
    my $item = self.bless(|%bless, :dc-subjects(@dc-subjects),
        :@media-contents, :@media-thumbnails, :$media-title, :$media-description,
        :itunes-author(%extra<itunes-author> // Str),
        :itunes-summary(%extra<itunes-summary> // Str),
        :itunes-duration(%extra<itunes-duration> // Str));
    Syndicate::Stats.record-item;
    $item
}

method XML {
    my $xml = XML::Element.new(:name<item>);
    $xml.attribs{'rdf:about'} = $.about if $.about.defined;
    add-element($xml, "title",       $.title);
    add-element($xml, "link",        $.link);
    add-element($xml, "description", $.summary);

    if $.content.defined && $.content.chars {
        $xml.append: XML::Element.new(:name<content:encoded>, :nodes([encode-entities($.content)]));
    }

    run-generators($xml, self);
    if $.updated.defined {
        add-dc-element($xml, "date", $.updated.Str);
    }
    for @.dc-subjects -> $s {
        add-dc-element($xml, "subject", $s);
    }
    $xml
}

method Str { $!cache-lock.protect: { $!cached-str //= ~self.XML } }

=begin pod

=head1 NAME

Syndicate::RSS::V1_0::Item - RSS 1.0 (RDF) item

=head1 DESCRIPTION

An RSS 1.0 item. Does L<C<Syndicate::Item>|rakudoc:Syndicate::Item>.

=head1 ATTRIBUTES

=item C<$.about> - RDF about URL
=item C<@.dc-subjects> - Dublin Core subjects

=end pod
