use v6.d;
use XML;
use Syndicate::Item;
use Syndicate::Utils;
use Syndicate::Extensions;
use Syndicate::Stats;

unit class Syndicate::RSS::V0_91::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

has Bool $.has-dc-creator;
has @.media-contents of Hash;
has @.media-thumbnails of Hash;
has Str $.media-title;
has Str $.media-description;
has Str $.itunes-author;
has Str $.itunes-summary;
has Str $.itunes-duration;

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    die "Invalid RSS 0.91 item XML: $!" unless $doc;
    die "Not an RSS 0.91 item element" unless $doc.root.name eq "item";
    self.from-xml($doc.root)
}

multi method new(XML::Element $xml-elem) {
    self.from-xml($xml-elem)
}

multi method from-xml(XML::Element $item-elem) {
    my $title = get-text-optional($item-elem, "title");
    my $link  = get-text-optional($item-elem, "link");
    my $desc  = get-text-optional($item-elem, "description");

    my %extra;
    run-parsers($item-elem, %extra);
    my $author = %extra<author> // Str;

    my @media-contents    = @(%extra<media-contents>    // []);
    my @media-thumbnails  = @(%extra<media-thumbnails>  // []);
    my $media-title       = %extra<media-title>         // Str;
    my $media-description = %extra<media-description>   // Str;

    CATCH {
        Syndicate::Stats.record-error;
        .rethrow;
    }
    Syndicate::Stats.record-item;
    self.bless(:$title, :$link, :summary($desc), :$author, :id($link // Str),
        :has-dc-creator(%extra<has-dc-creator> // False),
        :@media-contents, :@media-thumbnails, :$media-title, :$media-description,
        :itunes-author(%extra<itunes-author> // Str),
        :itunes-summary(%extra<itunes-summary> // Str),
        :itunes-duration(%extra<itunes-duration> // Str))
}

method XML {
    my $xml = XML::Element.new(:name<item>);
    add-element($xml, "title",       $.title);
    add-element($xml, "link",        $.link);
    add-element($xml, "description", $.summary);
    run-generators($xml, self);
    $xml
}

method Str { ~self.XML }

=begin pod

=head1 NAME

Syndicate::RSS::V0_91::Item - RSS 0.91 item

=head1 DESCRIPTION

An RSS 0.91 item. Does L<C<Syndicate::Item>|rakudoc:Syndicate::Item>.
Only supports title, link, and description — no metadata fields.

=end pod
