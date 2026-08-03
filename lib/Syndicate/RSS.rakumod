use v6.d;
use XML;
use Syndicate::Feed;
use Syndicate::RSS::Common;
use Syndicate::RSS::Item;
use Syndicate::Utils;
use Syndicate::Extension::DublinCore;
use Syndicate::Extension::MediaRSS;
use Syndicate::Extension::ITunes;
use Syndicate::Stats;
use Syndicate::Extensions;

unit class Syndicate::RSS:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed does Syndicate::RSS::Common;

has Str $.copyright;
has Str $.managingEditor;
has Str $.webMaster;
has DateTime $.pubDate;
has DateTime $.lastBuildDate;
has @!categories of Str is built;
method categories() { @!categories.List }
has Str $.docs;

method to-hash(:$clone = True) {
    my %h = self.to-hash-common(:$clone);
    %h<copyright>       = $.copyright       if $.copyright.defined;
    %h<managingEditor>  = $.managingEditor  if $.managingEditor.defined;
    %h<webMaster>       = $.webMaster       if $.webMaster.defined;
    %h<pubDate>         = $.pubDate.Str     if $.pubDate.defined;
    %h<lastBuildDate>   = $.lastBuildDate.Str if $.lastBuildDate.defined;
    %h<categories>      = @!categories.List if @!categories;
    %h<docs>            = $.docs            if $.docs.defined;
    %h<ttl>             = $.ttl             if $.ttl.defined;
    my %image = sanitize(%.image);
    %h<image>           = %image           if %image;
    %h<itunes-author>   = $.itunes-author   if $.itunes-author.defined;
    %h<itunes-summary>  = $.itunes-summary  if $.itunes-summary.defined;
    %h<atom-self-link>  = $.atom-self-link  if $.atom-self-link.defined;
    %h
}
has Int $.ttl;
has %.image;
has Str $.itunes-author;
has Str $.itunes-summary;
has Str $.atom-self-link;

multi method new(XML::Document $doc) {
    with-error-recording {
        my $rss = $doc.root;
        die "Not an RSS feed" unless $rss.name eq "rss";
        my $ver = $rss.attribs<version> // "2.0";
        die "Unsupported RSS version: $ver" unless $ver eq "2.0";
        my $channel = $rss.elements(:TAG<channel>)[0];
        die "No channel element" unless $channel;

        my %common = self.parse-channel-common($channel);
        my $title   = %common<title>;
        my $link    = %common<link>;
        my $desc    = %common<description>;
        my $lang    = %common<language>;
        my $cpy     = %common<copyright>;
        my $me      = %common<managing-editor>;
        my $wm      = %common<web-master>;
        my $pd      = %common<pub-date>;
        my $lbd     = %common<last-build-date>;
        my $gen     = %common<generator>;
        my $docs    = %common<docs>;
        my %image   = self.parse-image($channel);
        my $it-author  = %common<itunes-author>;
        my $it-summary = %common<itunes-summary>;
        my @categories = parse-categories($channel);
        my $ttl-str = get-text-optional($channel, "ttl");

        my $atom-self-link = Str;
        for elements-by-local-ns($channel, NS-ATOM, "link", "atom") -> $l {
            next unless ($l.attribs<rel> // "") eq "self";
            my $href = decode-entities($l.attribs<href> // Str);
            if $href.defined && $href.chars {
                $atom-self-link = $href;
                last;
            }
        }

        my @items;
        my $feed-active = set-active(active-extensions, $rss);
        for $channel.elements(:TAG<item>) -> $item-elem {
            my $item = Syndicate::RSS::Item.from-xml($item-elem, :active($feed-active));
            @items.push: $item;
        }

        my %bless = :$title, :$link, :description($desc),
            :language($lang), :copyright($cpy),
            :managingEditor($me), :webMaster($wm),
            :generator($gen), :docs($docs),
            :image(%image),
            :itunes-author($it-author), :itunes-summary($it-summary),
            :$atom-self-link;
        %bless<pubDate> = $pd if $pd ~~ DateTime;
        %bless<lastBuildDate> = $lbd if $lbd ~~ DateTime;
        if $ttl-str.defined && $ttl-str.chars {
            my $ttl = try { $ttl-str.Int };
            if $ttl.defined {
                %bless<ttl> = $ttl;
            } else {
                Syndicate::Stats.record-error;
            }
        }
        # with-error-recording records a Stats error and rethrows for any
        # exception raised anywhere in the constructor body above.
        self.bless(|%bless, :@categories, :@items)
    }
}

method TWEAK {
    self!apply-item-needs(@!items, $.itunes-author, $.itunes-summary)
}

method !build-xml {
    my $xml = XML::Element.new(:name<rss>, :attribs({:version('2.0')}));
    add-dc-declaration($xml)    if $!needs-dc;
    add-media-declaration($xml) if $!needs-media;
    add-itunes-declaration($xml) if $!needs-itunes;
    $xml.attribs{'xmlns:content'} = NS-CONTENT if $!needs-content;
    if $.atom-self-link.defined {
        $xml.attribs{'xmlns:atom'} = NS-ATOM;
    }
    my $channel = XML::Element.new(:name<channel>);
    $xml.append: $channel;

    add-element($channel, "title",          $.title);
    add-element($channel, "link",           $.link);
    add-element($channel, "description",    $.description);
    add-element($channel, "language",       $.language);
    add-element($channel, "copyright",      $.copyright);
    add-element($channel, "managingEditor", $.managingEditor);
    add-element($channel, "webMaster",      $.webMaster);
    add-itunes-element($channel, "author", $.itunes-author) if $.itunes-author.defined;
    add-itunes-element($channel, "summary", $.itunes-summary) if $.itunes-summary.defined;

    if $.pubDate.defined {
        $channel.append: XML::Element.new(:name<pubDate>, :nodes([RFC2822-FORMAT.to-string($.pubDate)]));
    }
    if $.lastBuildDate.defined {
        $channel.append: XML::Element.new(:name<lastBuildDate>, :nodes([RFC2822-FORMAT.to-string($.lastBuildDate)]));
    }

    add-element($channel, "category",  $_) for @!categories;
    add-element($channel, "generator", $.generator);
    add-element($channel, "docs",      $.docs);
    add-element($channel, "ttl",       ~$.ttl) if $.ttl.defined;

    self.build-xml-image($channel, %.image) if %.image<url>.defined || %.image<title>.defined;

    if $.atom-self-link.defined {
        $channel.append: XML::Element.new(
            :name<atom:link>,
            :attribs({ :href(encode-entities($.atom-self-link)), :rel<self>, :type('application/rss+xml') })
        );
    }

    $channel.append: $_.XML for @.items;

    $xml
}

=begin pod

=head1 NAME

Syndicate::RSS - RSS 2.0 feed

=head1 SYNOPSIS

=begin code :lang<raku>
my $feed = Syndicate::RSS.new($xml-string);
my $feed = Syndicate::RSS.new(:title("My Feed"), :link("https://example.com"), ...);
say ~$feed;  # XML output
=end code

=head1 DESCRIPTION

Parses and generates RSS 2.0 feeds. Does L<C<Syndicate::Feed>|rakudoc:Syndicate::Feed>
and L<C<Syndicate::RSS::Common>|rakudoc:Syndicate::RSS::Common>.

Supports iTunes podcast and Media RSS extensions via the extension registry.

=head1 ATTRIBUTES

=item C<$.title>, C<$.link>, C<$.description> - from Feed role
=item C<$.generator>, C<$.language> - from Feed role
=item C<$.copyright> - Copyright notice
=item C<$.managingEditor> - Managing editor email
=item C<$.webMaster> - Webmaster email
=item C<$.pubDate> - Publication date (L<C<DateTime>|rakudoc:DateTime>)
=item C<$.lastBuildDate> - Last build date (L<C<DateTime>|rakudoc:DateTime>)
=item C<@.categories> - Feed categories
=item C<$.docs> - Documentation URL
=item C<$.ttl> - Time to live (minutes)
=item C<%.image> - Feed image hash (url, title, link, width, height)
=item C<$.itunes-author> - iTunes author
=item C<$.itunes-summary> - iTunes summary

=head1 METHODS

=item C<new(Str $xml)> - Parse RSS 2.0 XML string
=item C<new(:$title, :$link, ...)> - Construct with named args
=item C<XML> - Returns L<C<XML::Element>|rakudoc:XML::Element>
=item C<Str> - Returns XML string

=end pod
