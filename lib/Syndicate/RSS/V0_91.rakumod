use v6.d;
use XML;
use Syndicate::Feed;
use Syndicate::RSS::Common;
use Syndicate::RSS::V0_91::Item;
use Syndicate::Utils;
use Syndicate::Extension::DublinCore;
use Syndicate::Extension::MediaRSS;
use Syndicate::Extension::ITunes;
use Syndicate::Stats;
use Syndicate::Extensions;

unit class Syndicate::RSS::V0_91:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed does Syndicate::RSS::Common;

has Str $.copyright;
has Str $.managingEditor;
has Str $.webMaster;
has Str $.rating;
has Str $.docs;
has DateTime $.pubDate;
has DateTime $.lastBuildDate;
has %.image;
has %.textInput of Str;
has @.skipHours of Int;
has @.skipDays of Str;
has Str $.itunes-author;
has Str $.itunes-summary;

method to-hash {
    my %h = self.to-hash-common;
    %h<copyright>       = $.copyright       if $.copyright.defined;
    %h<managingEditor>  = $.managingEditor  if $.managingEditor.defined;
    %h<webMaster>       = $.webMaster       if $.webMaster.defined;
    %h<rating>          = $.rating          if $.rating.defined;
    %h<docs>            = $.docs            if $.docs.defined;
    %h<pubDate>         = $.pubDate.Str     if $.pubDate.defined;
    %h<lastBuildDate>   = $.lastBuildDate.Str if $.lastBuildDate.defined;
    %h<image>           = %.image           if %.image;
    %h<textInput>       = %.textInput       if %.textInput;
    %h<skipHours>       = @.skipHours       if @.skipHours;
    %h<skipDays>        = @.skipDays        if @.skipDays;
    %h<itunes-author>   = $.itunes-author   if $.itunes-author.defined;
    %h<itunes-summary>  = $.itunes-summary  if $.itunes-summary.defined;
    %h
}

multi method new(XML::Document $doc) {
    with-error-recording {
        my $rss = $doc.root;
        die "Not an RSS feed" unless $rss.name eq "rss";
        my $ver = $rss.attribs<version> // "";
        die "Not RSS 0.91 (version: $ver)" unless $ver eq "0.91";
        my $channel = $rss.elements(:TAG<channel>)[0];
        die "No channel element" unless $channel;

        my %common = self.parse-channel-common($channel);
        my $title   = %common<title>;
        my $link    = %common<link>;
        my $desc    = %common<description>;
        my $lang    = %common<language>;
        my $gen     = %common<generator>;
        my $cpy     = %common<copyright>;
        my $me      = %common<managing-editor>;
        my $wm      = %common<web-master>;
        my $docs    = %common<docs>;
        my $pd      = %common<pub-date>;
        my $lbd     = %common<last-build-date>;
        my %image   = self.parse-image($channel);
        my $it-author  = %common<itunes-author>;
        my $it-summary = %common<itunes-summary>;
        my $rating  = get-text-optional($channel, "rating");
        my %textInput = self.parse-textinput($channel);
        my @skipHours = self.parse-skip-hours($channel);
        my @skipDays  = self.parse-skip-days($channel);

        my @items;
        my $feed-active = set-active(active-extensions, $rss);
        for $channel.elements(:TAG<item>) -> $item-elem {
            # Per the RSS 0.91 DTD every item requires title, link, and description.
            unless has-nonempty-text($item-elem, "title")
                && has-nonempty-text($item-elem, "link")
                && has-nonempty-text($item-elem, "description") {
                Syndicate::Stats.record-error;
                next;
            }
            my $item = Syndicate::RSS::V0_91::Item.from-xml($item-elem, :active($feed-active));
            @items.push: $item;
        }

        my %bless = :$title, :$link, :description($desc),
            :language($lang), :generator($gen), :copyright($cpy),
            :managingEditor($me), :webMaster($wm),
            :rating($rating), :$docs,
            :image(%image), :textInput(%textInput),
            :itunes-author($it-author), :itunes-summary($it-summary);
        %bless<pubDate> = $pd if $pd ~~ DateTime;
        %bless<lastBuildDate> = $lbd if $lbd ~~ DateTime;
        self.bless(|%bless, :@items, :skipHours(@skipHours), :skipDays(@skipDays))
    }
}

method !type-name { "RSS 0.91" }

method TWEAK {
    self!apply-item-needs(@!items, $.itunes-author, $.itunes-summary)
}

method !build-xml {
    my $xml = XML::Element.new(:name<rss>, :attribs({:version('0.91')}));
    my $channel = XML::Element.new(:name<channel>);
    $xml.append: $channel;

    add-dc-declaration($xml)        if $!needs-dc;
    add-media-declaration($xml)     if $!needs-media;
    add-itunes-declaration($xml)    if $!needs-itunes;
    $xml.attribs{'xmlns:content'} = NS-CONTENT if $!needs-content;

    add-element($channel, "title",          $.title);
    add-element($channel, "link",           $.link);
    add-element($channel, "description",    $.description);
    add-element($channel, "language",       $.language);
    add-element($channel, "rating",         $.rating);
    add-element($channel, "copyright",      $.copyright);
    add-element($channel, "docs",           $.docs);
    add-element($channel, "managingEditor", $.managingEditor);
    add-element($channel, "webMaster",      $.webMaster);
    add-element($channel, "generator",     $.generator);

    if $.pubDate.defined {
        $channel.append: XML::Element.new(:name<pubDate>, :nodes([RFC2822-FORMAT.to-string($.pubDate)]));
    }
    if $.lastBuildDate.defined {
        $channel.append: XML::Element.new(:name<lastBuildDate>, :nodes([RFC2822-FORMAT.to-string($.lastBuildDate)]));
    }

    self.build-xml-image($channel, %.image) if %.image<url>.defined || %.image<title>.defined;
    self.build-xml-textinput($channel, %.textInput) if %.textInput<title>.defined || %.textInput<name>.defined;
    self.build-xml-skip-hours($channel, @.skipHours);
    self.build-xml-skip-days($channel, @.skipDays);

    add-itunes-element($channel, "author", $.itunes-author) if $.itunes-author.defined;
    add-itunes-element($channel, "summary", $.itunes-summary) if $.itunes-summary.defined;

    $channel.append: $_.XML for @.items;

    $xml
}

method parse-textinput($channel --> Hash) {
    my %textInput;
    # Per RSS 0.91 DTD the element is <textInput> (camelCase), but some
    # feeds use <textinput> (all lowercase). Accept both for leniency.
    with ($channel.elements(:TAG<textInput>)[0] // $channel.elements(:TAG<textinput>)[0]) {
        %textInput<title>       = get-text-optional($_, "title");
        %textInput<description> = get-text-optional($_, "description");
        %textInput<name>        = get-text-optional($_, "name");
        %textInput<link>        = get-text-optional($_, "link");
    }
    %textInput
}

method parse-skip-hours($channel --> Array) {
    my @skipHours;
    with $channel.elements(:TAG<skipHours>)[0] {
        for .elements(:TAG<hour>) -> $h {
            my $val = element-text($h).trim;
            if $val ~~ /^\d+$/ {
                my $hour = $val.Int;
                @skipHours.push: $hour if 0 <= $hour <= 23;
            }
        }
    }
    @skipHours
}

method parse-skip-days($channel --> Array) {
    my constant %DAYS = Map.new: %(
        Monday => True, Tuesday => True, Wednesday => True,
        Thursday => True, Friday => True, Saturday => True, Sunday => True,
    );
    my @skipDays;
    with $channel.elements(:TAG<skipDays>)[0] {
        for .elements(:TAG<day>) -> $d {
            my $val = decode-entities(element-text($d)).tclc;
            @skipDays.push: $val if %DAYS{$val}:exists;
        }
    }
    @skipDays
}

=begin pod

=head1 NAME

Syndicate::RSS::V0_91 - RSS 0.91 feed

=head1 SYNOPSIS

=begin code :lang<raku>
my $feed = Syndicate::RSS::V0_91.new($xml-string);
say ~$feed;
=end code

=head1 DESCRIPTION

Parses and generates RSS 0.91 feeds. Does L<C<Syndicate::Feed>|rakudoc:Syndicate::Feed>
and L<C<Syndicate::RSS::Common>|rakudoc:Syndicate::RSS::Common>.

=head1 ATTRIBUTES

=item C<$.title>, C<$.link>, C<$.description> - from Feed role
=item C<$.generator>, C<$.language> - from Feed role
=item C<$.copyright> - Copyright notice
=item C<$.managingEditor> - Managing editor
=item C<$.webMaster> - Webmaster
=item C<$.rating> - PICS rating
=item C<$.docs> - Documentation URL
=item C<$.pubDate> - Publication date
=item C<$.lastBuildDate> - Last build date
=item C<%.image> - Image hash
=item C<%.textInput> - Text input hash
=item C<@.skipHours> - Hours to skip
=item C<@.skipDays> - Days to skip

=end pod
