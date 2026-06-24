use v6.d;
use XML;
use Syndicate::Feed;
use Syndicate::RSS::Common;
use Syndicate::RSS::V1_0::Item;
use Syndicate::Utils;
use Syndicate::Extension::DublinCore;
use Syndicate::Extension::MediaRSS;
use Syndicate::Extension::ITunes;
use Syndicate::Stats;

unit class Syndicate::RSS::V1_0:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed does Syndicate::RSS::Common;

has Str $.about;
has %.image of Str;
has Bool $!needs-dc;
has Bool $!needs-media;
has Bool $!needs-itunes;
# 'is built' is a standard Raku mechanism that allows setting a private
# attribute via the constructor without exposing a public accessor.
has Bool $!lang-from-dc is built;

submethod TWEAK {
    $!lang-from-dc //= False;
    $!needs-dc    = $!lang-from-dc || $!language.defined;
    $!needs-media = False;
    $!needs-itunes = False;
    for @!items {
        $!needs-dc      ||= .?has-dc-creator || .?updated.defined
                         || ( .?dc-subjects.defined && .?dc-subjects.elems > 0 );
        $!needs-media   ||= ?(.?media-contents) || ?(.?media-thumbnails) || .?media-title.defined || .?media-description.defined;
        $!needs-itunes  ||= .?itunes-author.defined || .?itunes-summary.defined || .?itunes-duration.defined;
        last if $!needs-dc && $!needs-media && $!needs-itunes;
    }
}

multi method new(XML::Document $doc) {
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
    my $lang-from-dc = False;
    if $lang.defined {
        $lang-from-dc = False;
    } else {
        $lang = get-dc-text($channel, "language");
        $lang-from-dc = True if $lang.defined;
    }

    my %image;
    with $root.elements(:TAG<image>)[0] -> $img {
        %image<url>   = get-text-optional($img, "url");
        %image<title> = get-text-optional($img, "title");
        %image<link>  = get-text-optional($img, "link");
        %image<about> = $img.attribs{'rdf:about'} // $img.attribs<about> // Str;
    }

    my @items;
    for $root.elements(:TAG<item>) -> $item-elem {
        @items.push: Syndicate::RSS::V1_0::Item.from-xml($item-elem);
    }

    CATCH {
        Syndicate::Stats.record-error;
        .rethrow;
    }
    self.bless(:$about, :$title, :$link, :description($desc),
               :generator($gen), :language($lang),
               :image(%image),
               :lang-from-dc($lang-from-dc),
               :@items)
}

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    unless $doc {
        Syndicate::Stats.record-error;
        die "Invalid RSS 1.0 XML: $!";
    }
    self.new($doc)
}

method XML {
    my $root = XML::Element.new(:name<rdf:RDF>, :attribs({
        'xmlns:rdf' => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
        'xmlns'     => 'http://purl.org/rss/1.0/'
    }));
    add-dc-declaration($root)    if $!needs-dc;
    add-media-declaration($root) if $!needs-media;
    add-itunes-declaration($root) if $!needs-itunes;

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
        my $resource = $item.?about // $item.link // Str;
        $li.attribs{'rdf:resource'} = $resource if $resource.defined && $resource.chars;
        $seq.append: $li;
    }

    self.build-xml-image($root, %.image, :rdf-about) if %.image<url>.defined || %.image<title>.defined;

    $root.append: $_.XML for @.items;

    return $root;
}

method Str {
    $!str-lock.protect: {
        unless $!cached-str.defined {
            $!cached-str = '<?xml version="1.0" encoding="UTF-8"?>' ~ "\n" ~ ~self.XML
        }
    }
    $!cached-str
}

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
