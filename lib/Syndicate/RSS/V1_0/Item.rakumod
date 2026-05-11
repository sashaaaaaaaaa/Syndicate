use v6.d;
use XML;
use Syndicate::Item;
use Syndicate::Utils;
use Syndicate::Extension::DublinCore;

unit class Syndicate::RSS::V1_0::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

has Str $.about;
has @.dc-subjects;

multi method new(Str $xml) {
    my $doc = XML::Document.new($xml);
    self.new-from-xml($doc.root)
}

multi method new(XML::Element $xml-elem) {
    self.new-from-xml($xml-elem)
}

proto method new-from-xml(|) {*}
multi method new-from-xml(XML::Element $item-elem) {
    my $about   = $item-elem.attribs{'rdf:about'} // $item-elem.attribs<about> // Str;
    my $title   = get-text($item-elem, "title");
    my $link    = get-text($item-elem, "link");
    my $desc    = get-text-optional($item-elem, "description");

    my $author  = get-text-optional($item-elem, "author");
    $author //= get-dc-text($item-elem, "creator");

    my $dc-date = get-dc-text($item-elem, "date");
    my $updated = parse-date($dc-date);

    my @dc-subjects = get-dc-texts($item-elem, "subject");

    my $item-id = $about // $link // Str;
    my %bless = :$about, :$title, :$link, :summary($desc),
                :$author,
                :id($item-id),
                :content($desc // Str);
    %bless<updated> = $updated if $updated ~~ DateTime;
    self.bless(|%bless, :dc-subjects(@dc-subjects))
}

method XML {
    my $xml = XML::Element.new(:name<item>);
    $xml.attribs{'rdf:about'} = $.about if $.about.defined;
    $xml.append: XML::Element.new(:name<title>, :nodes([$.title])) if $.title.defined;
    $xml.append: XML::Element.new(:name<link>, :nodes([$.link])) if $.link.defined;
    $xml.append: XML::Element.new(:name<description>, :nodes([$.summary])) if $.summary.defined;

    add-dc-element($xml, "creator", $.author) if $.author.defined;
    if $.updated.defined {
        add-dc-element($xml, "date", $.updated.Str);
    }
    for @.dc-subjects -> $s {
        add-dc-element($xml, "subject", $s);
    }
    $xml
}

method Str { ~self.XML }

=begin pod

=head1 NAME

Syndicate::RSS::V1_0::Item - RSS 1.0 (RDF) item

=head1 DESCRIPTION

An RSS 1.0 item. Does L<C<Syndicate::Item>|rakudoc:Syndicate::Item>.

=head1 ATTRIBUTES

=item C<$.about> - RDF about URL
=item C<@.dc-subjects> - Dublin Core subjects

=end pod
