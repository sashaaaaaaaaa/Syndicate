use v6.d;
use XML;
use Syndicate::Feed;
use Syndicate::RSS::V1_0::Item;
use Syndicate::Utils;
use Syndicate::Extension::DublinCore;

unit class Syndicate::RSS::V1_0:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed;

has Str $.about;
has %.image;

multi method new(Str $xml) {
    my $doc = XML::Document.new($xml);
    my $root = $doc.root;
    die "Not RSS 1.0" unless $root.name eq "rdf:RDF" || $root.name eq "RDF";
    my $channel = $root.elements(:TAG<channel>)[0];
    die "No channel element" unless $channel;

    my $about = $channel.attribs{'rdf:about'} // $channel.attribs<about> // Str;
    my $title = get-text($channel, "title");
    my $link  = get-text($channel, "link");
    my $desc  = get-text($channel, "description");
    my $gen   = get-text-optional($channel, "generator");
    my $lang  = get-text-optional($channel, "language");

    my %image;
    with $root.elements(:TAG<image>)[0] -> $img {
        %image<url>   = get-text($img, "url");
        %image<title> = get-text($img, "title");
        %image<link>  = get-text($img, "link");
        %image<about> = $img.attribs{'rdf:about'} // $img.attribs<about> // Str;
    }

    my @items;
    for $root.elements(:TAG<item>) -> $item-elem {
        @items.push: Syndicate::RSS::V1_0::Item.new-from-xml($item-elem);
    }

    self.bless(:$about, :$title, :$link, :description($desc),
               :generator($gen), :language($lang),
               :image(%image),
               :@items)
}

method XML {
    my $root = XML::Element.new(:name<rdf:RDF>, :attribs({
        'xmlns:rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
        'xmlns'     => 'http://purl.org/rss/1.0/'
    }));
    add-dc-declaration($root) if $.language.defined
        || @.items.first({ .?author.defined || .?updated.defined
            || ( .?dc-subjects && .?dc-subjects.elems > 0 ) });

    my $channel = XML::Element.new(:name<channel>);
    $channel.attribs{'rdf:about'} = $.about if $.about.defined;
    $root.append: $channel;

    $channel.append: XML::Element.new(:name<title>, :nodes([encode-entities($.title)])) if $.title.defined;
    $channel.append: XML::Element.new(:name<link>, :nodes([encode-entities($.link)])) if $.link.defined;
    $channel.append: XML::Element.new(:name<description>, :nodes([encode-entities($.description)])) if $.description.defined;
    $channel.append: XML::Element.new(:name<generator>, :nodes([encode-entities($.generator)])) if $.generator.defined;
    add-dc-element($channel, "language", $.language) if $.language.defined;

    if %.image<about>.defined {
        my $img-ref = XML::Element.new(:name<image>);
        $img-ref.attribs{'rdf:resource'} = %.image<about>;
        $channel.append: $img-ref;
    }

    my $items-wrapper = XML::Element.new(:name<items>);
    $channel.append: $items-wrapper;
    my $seq = XML::Element.new(:name<rdf:Seq>);
    $items-wrapper.append: $seq;
    for @.items -> $item {
        my $li = XML::Element.new(:name<rdf:li>);
        my $resource = $item.link // $item.?about // Str;
        $li.attribs{'rdf:resource'} = $resource if $resource.defined && $resource.chars;
        $seq.append: $li;
    }

    if %.image<url>.defined || %.image<title>.defined {
        my $img = XML::Element.new(:name<image>);
        $img.attribs{'rdf:about'} = %.image<about> if %.image<about>.defined;
        $img.append: XML::Element.new(:name<title>, :nodes([encode-entities(%.image<title>)])) if %.image<title>.defined;
        $img.append: XML::Element.new(:name<url>, :nodes([encode-entities(%.image<url>)])) if %.image<url>.defined;
        $img.append: XML::Element.new(:name<link>, :nodes([encode-entities(%.image<link>)])) if %.image<link>.defined;
        $root.append: $img;
    }

    $root.append: $_.XML for @.items;

    return $root;
}

method Str { '<?xml version="1.0" encoding="UTF-8"?>' ~ "\n" ~ ~self.XML }

=begin pod

=head1 NAME

Syndicate::RSS::V1_0 - RSS 1.0 (RDF) feed

=head1 SYNOPSIS

=begin code :lang<raku>
my $feed = Syndicate::RSS::V1_0.new($xml-string);
say ~$feed;
=end code

=head1 DESCRIPTION

Parses and generates RSS 1.0 (RDF-based) feeds. Does L<C<Syndicate::Feed>|rakudoc:Syndicate::Feed>.

=head1 ATTRIBUTES

=item C<$.title>, C<$.link>, C<$.description> - from Feed role
=item C<$.generator>, C<$.language> - from Feed role
=item C<$.about> - RDF about URL
=item C<%.image> - Image hash (url, title, link, about)

=end pod
