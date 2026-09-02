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
use Syndicate::Extensions;

my constant NS-RSS1    = 'http://purl.org/rss/1.0/';

unit class Syndicate::RSS::V1_0:ver<0.0.6>:auth<zef:sasha> does Syndicate::Feed does Syndicate::RSS::Common;

has Str $.about;
has %.image;
has Str $.itunes-author;
has Str $.itunes-summary;
# 'is built' is a standard Raku mechanism that allows setting a private
# attribute via the constructor without exposing a public accessor.
has @!categories of Str is built;
method categories() { @!categories.List }

method to-hash(:$clone = True) {
    my %h = self.to-hash-common(:$clone);
    %h<about>          = $.about           if $.about.defined;
    my %image = sanitize(%.image);
    %h<image>          = %image            if %image;
    %h<categories>     = @!categories.List if @!categories;
    %h<itunes-author>  = $.itunes-author   if $.itunes-author.defined;
    %h<itunes-summary> = $.itunes-summary  if $.itunes-summary.defined;
    %h
}

multi method new(XML::Document $doc) {
    with-error-recording {
        my $root = $doc.root;
        die "Not RSS 1.0" unless $root.name eq "rdf:RDF" || $root.name eq "RDF";
        my $channel = $root.elements(:TAG<channel>)[0];
        die "No channel element" unless $channel;

        my $about = decode-entities($channel.attribs{'rdf:about'} // $channel.attribs<about> // Str);
        my %common = self.parse-channel-common($channel);
        my $title   = %common<title>;
        my $link    = %common<link>;
        my $desc    = %common<description>;
        my $gen     = %common<generator>;
        my %image   = self.parse-image($root, :rdf-about);
        my $lang    = %common<language>;
        unless $lang.defined {
            $lang = get-dc-text($channel, "language");
        }

        my $it-author  = %common<itunes-author>;
        my $it-summary = %common<itunes-summary>;

        my @categories;
        for elements-by-local-ns($channel, NS-DC, "subject", "dc") -> $s {
            my $text = decode-entities(element-text($s)).trim;
            @categories.push: $text if $text.chars;
        }

        my @items;
        my $feed-active = set-active(active-extensions, $root);
        for $root.elements(:TAG<item>) -> $item-elem {
            unless has-nonempty-text($item-elem, "title") && has-nonempty-text($item-elem, "link") {
                Syndicate::Stats.record-error;
                next;
            }
            my $item = Syndicate::RSS::V1_0::Item.from-xml($item-elem, :active($feed-active));
            @items.push: $item;
        }

        self.bless(:$about, :$title, :$link, :description($desc),
                   :generator($gen), :language($lang),
                   :image(%image),
                   :itunes-author($it-author), :itunes-summary($it-summary),
                   :categories(@categories), :@items)
    }
}

method !type-name { "RSS 1.0" }

method TWEAK {
    self!apply-item-needs(@!items, $.itunes-author, $.itunes-summary);
    $!needs-dc ||= ?@!categories;
    # RSS 1.0 has no <language> element; the language is emitted as
    # <dc:language>, which requires the xmlns:dc declaration.
    $!needs-dc ||= $.language.defined;
}

method !build-xml {
    my $root = XML::Element.new(:name<rdf:RDF>, :attribs({
        'xmlns:rdf' => NS-RDF,
        'xmlns'     => NS-RSS1
    }));
    add-dc-declaration($root)    if $!needs-dc;
    add-media-declaration($root) if $!needs-media;
    add-itunes-declaration($root) if $!needs-itunes;
    $root.attribs{'xmlns:content'} = NS-CONTENT if $!needs-content;

    my $channel = XML::Element.new(:name<channel>);
    add-attrib($channel, 'rdf:about', $.about) if $.about.defined;
    $root.append: $channel;

    add-element($channel, "title",       $.title);
    add-element($channel, "link",        $.link);
    add-element($channel, "description", $.description);
    add-element($channel, "generator",   $.generator);
    add-itunes-element($channel, "author", $.itunes-author) if $.itunes-author.defined;
    add-itunes-element($channel, "summary", $.itunes-summary) if $.itunes-summary.defined;
    if $.language.defined {
        # RSS 1.0 has no <language> element; always use <dc:language> so the
        # value round-trips without emitting a non-standard element.
        add-dc-element($channel, "language", $.language);
    }
    add-dc-element($channel, "subject", $_) for @!categories;

    # Emit the channel image reference only when the root image element
    # (which carries the url/title/link) will actually be emitted; an
    # rdf:resource-only image would otherwise leave a dangling reference.
    if %.image<about>.defined && (%.image<url>.defined || %.image<title>.defined) {
        my $img-ref = XML::Element.new(:name<image>);
        add-attrib($img-ref, 'rdf:resource', %.image<about>);
        $channel.append: $img-ref;
    }

    my $items-wrapper = XML::Element.new(:name<items>);
    $channel.append: $items-wrapper;
    my $seq = XML::Element.new(:name<rdf:Seq>);
    $items-wrapper.append: $seq;
    for @.items -> $item {
        my $li = XML::Element.new(:name<rdf:li>);
        my $resource = $item.about // $item.link // Str;
        add-attrib($li, 'rdf:resource', $resource) if $resource.defined && $resource.chars;
        $seq.append: $li;
    }

    self.build-xml-image($root, %.image, :rdf-about) if %.image<url>.defined || %.image<title>.defined;

    $root.append: $_.XML for @.items;

    $root
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
