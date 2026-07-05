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

my constant NS-RDF     = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
my constant NS-RSS1    = 'http://purl.org/rss/1.0/';
my constant NS-CONTENT = 'http://purl.org/rss/1.0/modules/content/';

unit class Syndicate::RSS::V1_0:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed does Syndicate::RSS::Common;

has Str $.about;
has %.image;
has Bool $!needs-dc is built;
has Bool $!needs-media is built;
has Bool $!needs-content is built;
has Bool $!needs-itunes is built;
# 'is built' is a standard Raku mechanism that allows setting a private
# attribute via the constructor without exposing a public accessor.
has Bool $!lang-from-dc is built;

submethod TWEAK {
    $!lang-from-dc //= False;
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
    my $lang-elem = $channel.elements(:TAG<language>)[0];
    my $lang;
    my $lang-fallback = False;
    if $lang-elem {
        with $lang-elem.contents[0] -> $t {
            $lang = $t.?text;
        }
    }
    unless $lang.defined {
        # No <language> element or empty element — try Dublin Core fallback
        $lang = get-dc-text($channel, "language");
        $lang-fallback = True if $lang.defined;

    }

    my %image = self.parse-image($root, :rdf-about);

    my @items;
    my ($needs-dc, $needs-media, $needs-itunes, $needs-content);
    for $root.elements(:TAG<item>) -> $item-elem {
        my $title-el = $item-elem.elements(:TAG<title>)[0];
        my $link-el  = $item-elem.elements(:TAG<link>)[0];
        unless $title-el && $title-el.contents[0] && $title-el.contents[0].?text.trim.chars
            && $link-el && $link-el.contents[0] && $link-el.contents[0].?text.trim.chars {
            warn "Skipping RSS 1.0 item without title or link";
            next;
        }
        my $item = Syndicate::RSS::V1_0::Item.from-xml($item-elem);
        my ($dc, $media, $itunes, $content) = $item.namespace-flags;
        $needs-dc ||= $dc;
        $needs-media ||= $media;
        $needs-itunes ||= $itunes;
        $needs-content ||= $content;
        @items.push: $item;
    }

    CATCH {
        Syndicate::Stats.record-error;
        .rethrow;
    }
    self.bless(:$about, :$title, :$link, :description($desc),
               :generator($gen), :language($lang),
               :image(%image),
                :lang-from-dc($lang-fallback),
               :$needs-dc, :$needs-media, :$needs-itunes, :$needs-content,
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
        'xmlns:rdf' => NS-RDF,
        'xmlns'     => NS-RSS1
    }));
    add-dc-declaration($root)    if $!needs-dc;
    add-media-declaration($root) if $!needs-media;
    add-itunes-declaration($root) if $!needs-itunes;
    $root.attribs{'xmlns:content'} = NS-CONTENT if $!needs-content;

    my $channel = XML::Element.new(:name<channel>);
    $channel.attribs{'rdf:about'} = $.about if $.about.defined;
    $root.append: $channel;

    add-element($channel, "title",       $.title);
    add-element($channel, "link",        $.link);
    add-element($channel, "description", $.description);
    add-element($channel, "generator",   $.generator);
    add-element($channel, "language", $.language) if $.language.defined;

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
