use v6.d;
use XML;
use Syndicate::Feed;
use Syndicate::RSS::Common;
use Syndicate::RSS::V0_91::Item;
use DateTime::Format::RFC2822;
my constant $RFC2822 = DateTime::Format::RFC2822.new;
use Syndicate::Utils;
use Syndicate::Extension::DublinCore;
use Syndicate::Extension::MediaRSS;
use Syndicate::Extension::ITunes;
use Syndicate::Stats;

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
has Bool $!needs-dc;
has Bool $!needs-media;
has Bool $!needs-itunes;

submethod TWEAK {
    my $feed-itunes = $!itunes-author.defined || $!itunes-summary.defined;
    ($!needs-dc, $!needs-media, $!needs-itunes) = self!set-item-flags(:check-content(False));
    $!needs-itunes ||= $feed-itunes;
}

multi method new(XML::Document $doc) {
    my $rss = $doc.root;
    die "Not an RSS feed" unless $rss.name eq "rss";
    my $ver = $rss.attribs<version> // "";
    die "Not RSS 0.91 (version: $ver)" unless $ver eq "0.91";
    my $channel = $rss.elements(:TAG<channel>)[0];
    die "No channel element" unless $channel;

    my $title   = get-text($channel, "title");
    my $link    = get-text($channel, "link");
    my $desc    = get-text($channel, "description");
    my $lang    = get-text-optional($channel, "language");
    my $gen     = get-text-optional($channel, "generator");
    my $cpy     = get-text-optional($channel, "copyright");
    my $me      = get-text-optional($channel, "managingEditor");
    my $wm      = get-text-optional($channel, "webMaster");
    my $rating  = get-text-optional($channel, "rating");
    my $docs    = get-text-optional($channel, "docs");
    my $pd      = parse-date-optional(get-text-optional($channel, "pubDate"));
    my $lbd     = parse-date-optional(get-text-optional($channel, "lastBuildDate"));

    my %image     = self.parse-image($channel);
    my %textInput = self.parse-textinput($channel);
    my @skipHours = self.parse-skip-hours($channel);
    my @skipDays  = self.parse-skip-days($channel);

    my $it-author  = get-itunes-text($channel, "author");
    my $it-summary = get-itunes-text($channel, "summary");

    my @items;
    for $channel.elements(:TAG<item>) -> $item-elem {
        @items.push: Syndicate::RSS::V0_91::Item.from-xml($item-elem);
    }

    my %bless = :$title, :$link, :description($desc),
        :language($lang), :generator($gen), :copyright($cpy),
        :managingEditor($me), :webMaster($wm),
        :rating($rating), :$docs,
        :image(%image), :textInput(%textInput);
    %bless<pubDate> = $pd if $pd ~~ DateTime;
    %bless<lastBuildDate> = $lbd if $lbd ~~ DateTime;
    %bless<itunes-author> = $it-author if $it-author.defined;
    %bless<itunes-summary> = $it-summary if $it-summary.defined;
    CATCH {
        Syndicate::Stats.record-error;
        .rethrow;
    }
    self.bless(|%bless, :@items, :skipHours(@skipHours), :skipDays(@skipDays))
}

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    unless $doc {
        Syndicate::Stats.record-error;
        die "Invalid RSS 0.91 XML: $!";
    }
    self.new($doc)
}

method XML {
    my $xml = XML::Element.new(:name<rss>, :attribs({:version('0.91')}));
    my $channel = XML::Element.new(:name<channel>);
    $xml.append: $channel;

    add-element($channel, "title",          $.title);
    add-element($channel, "link",           $.link);
    add-element($channel, "description",    $.description);
    add-element($channel, "language",       $.language);
    add-element($channel, "rating",         $.rating);
    add-element($channel, "copyright",      $.copyright);
    add-element($channel, "docs",           $.docs);
    add-element($channel, "managingEditor", $.managingEditor);
    add-element($channel, "webMaster",      $.webMaster);

    if $.pubDate.defined {
        $channel.append: XML::Element.new(:name<pubDate>, :nodes([$RFC2822.to-string($.pubDate)]));
    }
    if $.lastBuildDate.defined {
        $channel.append: XML::Element.new(:name<lastBuildDate>, :nodes([$RFC2822.to-string($.lastBuildDate)]));
    }

    self.build-xml-image($channel, %.image) if %.image<url>.defined || %.image<title>.defined;
    self.build-xml-textinput($channel, %.textInput) if %.textInput<title>.defined || %.textInput<name>.defined;
    self.build-xml-skip-hours($channel, @.skipHours);
    self.build-xml-skip-days($channel, @.skipDays);

    add-itunes-element($channel, "author", $.itunes-author) if $.itunes-author.defined;
    add-itunes-element($channel, "summary", $.itunes-summary) if $.itunes-summary.defined;

    add-dc-declaration($xml)    if $!needs-dc;
    add-media-declaration($xml) if $!needs-media;
    add-itunes-declaration($xml) if $!needs-itunes;
    $channel.append: $_.XML for @.items;

    return $xml;
}

method parse-textinput($channel --> Hash) {
    my %textInput;
    with $channel.elements(:TAG<textinput>)[0] {
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
            with $h.contents[0] {
                if .text ~~ /^\d+$/ {
                    @skipHours.push: .text.Int;
                } else {
                    note "Non-numeric hour value in skipHours: {.text}";
                }
            }
        }
    }
    @skipHours
}

method parse-skip-days($channel --> Array) {
    my @skipDays;
    with $channel.elements(:TAG<skipDays>)[0] {
        for .elements(:TAG<day>) -> $d {
            with $d.contents[0] {
                @skipDays.push: .text.tclc;
            }
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
