use v6.d;
use XML;
use DateTime::Format::RFC2822;
use Syndicate::Feed;
use Syndicate::RSS::Common;
use Syndicate::RSS::V0_91::Item;
use Syndicate::Utils;

my constant $RFC2822 = DateTime::Format::RFC2822.new;

unit class Syndicate::RSS::V0_91:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed does Syndicate::RSS::Common;

has Str $.copyright;
has Str $.managingEditor;
has Str $.webMaster;
has Str $.rating;
has Str $.docs;
has DateTime $.pubDate;
has DateTime $.lastBuildDate;
has %.image;
has %.textInput;
has @.skipHours;
has @.skipDays;

multi method new(Str $xml) {
    my $doc = XML::Document.new($xml);
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

    my @items;
    for $channel.elements(:TAG<item>) -> $item-elem {
        @items.push: Syndicate::RSS::V0_91::Item.new-from-xml($item-elem);
    }

    my %bless = :$title, :$link, :description($desc),
        :language($lang), :copyright($cpy),
        :managingEditor($me), :webMaster($wm),
        :rating($rating), :$docs,
        :image(%image), :textInput(%textInput);
    %bless<pubDate> = $pd if $pd ~~ DateTime;
    %bless<lastBuildDate> = $lbd if $lbd ~~ DateTime;
    self.bless(|%bless, :@items, :skipHours(@skipHours), :skipDays(@skipDays))
}

method XML {
    my $xml = XML::Element.new(:name<rss>, :attribs({:version('0.91')}));
    my $channel = XML::Element.new(:name<channel>);
    $xml.append: $channel;

    $channel.append: XML::Element.new(:name<title>, :nodes([$.title])) if $.title.defined;
    $channel.append: XML::Element.new(:name<link>, :nodes([$.link])) if $.link.defined;
    $channel.append: XML::Element.new(:name<description>, :nodes([$.description])) if $.description.defined;
    $channel.append: XML::Element.new(:name<language>, :nodes([$.language])) if $.language.defined;
    $channel.append: XML::Element.new(:name<rating>, :nodes([$.rating])) if $.rating.defined;
    $channel.append: XML::Element.new(:name<copyright>, :nodes([$.copyright])) if $.copyright.defined;
    $channel.append: XML::Element.new(:name<docs>, :nodes([$.docs])) if $.docs.defined;
    $channel.append: XML::Element.new(:name<managingEditor>, :nodes([$.managingEditor])) if $.managingEditor.defined;
    $channel.append: XML::Element.new(:name<webMaster>, :nodes([$.webMaster])) if $.webMaster.defined;

    if $.pubDate.defined {
        $channel.append: XML::Element.new(:name<pubDate>, :nodes([$RFC2822.to-string($.pubDate)]));
    }
    if $.lastBuildDate.defined {
        $channel.append: XML::Element.new(:name<lastBuildDate>, :nodes([$RFC2822.to-string($.lastBuildDate)]));
    }

    self.build-xml-image($channel, %.image);
    self.build-xml-textinput($channel, %.textInput);
    self.build-xml-skip-hours($channel, @.skipHours);
    self.build-xml-skip-days($channel, @.skipDays);

    $channel.append: $_.XML for @.items;

    return $xml;
}

method Str { '<?xml version="1.0" encoding="UTF-8"?>' ~ "\n" ~ ~self.XML }

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
