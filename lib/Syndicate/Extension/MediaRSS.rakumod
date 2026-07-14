use v6.d;
use XML;
use Syndicate::Extensions;
use Syndicate::Utils;

my constant NS-MEDIA is export = 'http://search.yahoo.com/mrss/';

unit module Syndicate::Extension::MediaRSS:ver<0.0.1>:auth<zef:sasha>;

register-ext(:namespace<media>,
    parse => sub ($elem, %attrs) {
        return unless $elem.elements.first({ .name.starts-with('media:') });
        my @mc = get-media-contents($elem);
        %attrs<media-contents> = @mc if @mc;
        my @mt = get-media-thumbnails($elem);
        %attrs<media-thumbnails> = @mt if @mt;
        my @mg = get-media-groups($elem);
        %attrs<media-groups> = @mg if @mg;
        with get-media-text($elem, "title")       { %attrs<media-title>       = $_ }
        with get-media-text($elem, "description") { %attrs<media-description> = $_ }
    },
    generate => sub ($xml, $item) {
        add-media-content-element($xml, $_) for @($item.?media-contents // []);
        add-media-thumbnail-element($xml, $_) for @($item.?media-thumbnails // []);
        add-media-group-element($xml, $_) for @($item.?media-groups // []);
        with $item.?media-title -> $v {
            $xml.append: XML::Element.new(:name<media:title>, :nodes([encode-entities($v)])) if $v.chars;
        }
        with $item.?media-description -> $v {
            $xml.append: XML::Element.new(:name<media:description>, :nodes([encode-entities($v)])) if $v.chars;
        }
    }
);

sub get-media-text($parent, Str $tag --> Str) is export {
    with $parent.elements(:TAG("media:$tag"))[0] -> $e {
        with $e.contents[0] -> $t {
            my $text = ($t.?text // "").trim;
            return $text.defined && $text.chars ?? decode-entities($text) !! Str;
        }
    }
    Str
}

sub get-media-contents($parent --> Array) is export {
    my @contents;
    for $parent.elements(:TAG<media:content>) -> $e {
        my %c;
        %c<url>      = $e.attribs<url>      // Str;
        %c<type>     = $e.attribs<type>     // Str;
        %c<medium>   = $e.attribs<medium>   // Str;
        %c<duration> = try +$e.attribs<duration> // $e.attribs<duration> if $e.attribs<duration>.defined;
        %c<fileSize> = +$e.attribs<fileSize> if $e.attribs<fileSize>.defined;
        %c<width>    = +$e.attribs<width>    if $e.attribs<width>.defined;
        %c<height>   = +$e.attribs<height>   if $e.attribs<height>.defined;
        @contents.push: %c;
    }
    @contents
}

sub get-media-thumbnails($parent --> Array) is export {
    my @thumbs;
    for $parent.elements(:TAG<media:thumbnail>) -> $e {
        my %t;
        %t<url>    = $e.attribs<url>    // Str;
        %t<width>  = +$e.attribs<width>  if $e.attribs<width>.defined;
        %t<height> = +$e.attribs<height> if $e.attribs<height>.defined;
        %t<time>   = $e.attribs<time>    // Str;
        @thumbs.push: %t;
    }
    @thumbs
}

sub add-media-declaration(XML::Element $root --> Nil) is export {
    $root.attribs{'xmlns:media'} = NS-MEDIA
        unless $root.attribs{'xmlns:media'}.defined;
}

sub add-media-content-element(XML::Element $parent, %content --> Nil) is export {
    my $e = XML::Element.new(:name<media:content>);
    $e.attribs<url>      = encode-entities(%content<url>)      if %content<url>.defined;
    $e.attribs<type>     = encode-entities(%content<type>)     if %content<type>.defined;
    $e.attribs<medium>   = encode-entities(%content<medium>)   if %content<medium>.defined;
    $e.attribs<duration> = encode-entities(~%content<duration>) if %content<duration>.defined;
    $e.attribs<fileSize> = encode-entities(~%content<fileSize>) if %content<fileSize>.defined;
    $e.attribs<width>    = encode-entities(~%content<width>)    if %content<width>.defined;
    $e.attribs<height>   = encode-entities(~%content<height>)   if %content<height>.defined;
    $parent.append: $e;
}

sub get-media-groups($parent --> Array) is export {
    my @groups;
    for $parent.elements(:TAG<media:group>) -> $g {
        my @gc = get-media-contents($g);
        my @gt = get-media-thumbnails($g);
        next unless @gc || @gt;
        my %group;
        %group<media-contents>   = @gc if @gc;
        %group<media-thumbnails> = @gt if @gt;
        @groups.push: %group;
    }
    @groups
}

sub add-media-group-element(XML::Element $parent, %group --> Nil) is export {
    my $e = XML::Element.new(:name<media:group>);
    add-media-content-element($e, $_) for @(%group<media-contents> // []);
    add-media-thumbnail-element($e, $_) for @(%group<media-thumbnails> // []);
    $parent.append: $e;
}

sub add-media-thumbnail-element(XML::Element $parent, %thumb --> Nil) is export {
    my $e = XML::Element.new(:name<media:thumbnail>);
    $e.attribs<url>    = encode-entities(%thumb<url>)    if %thumb<url>.defined;
    $e.attribs<width>  = encode-entities(~%thumb<width>)  if %thumb<width>.defined;
    $e.attribs<height> = encode-entities(~%thumb<height>) if %thumb<height>.defined;
    $e.attribs<time>   = encode-entities(%thumb<time>)   if %thumb<time>.defined;
    $parent.append: $e;
}

=begin pod

=head1 NAME

Syndicate::Extension::MediaRSS - Media RSS (MRSS) extension

=head1 DESCRIPTION

Automatically registers with L<C<Syndicate::Extensions>|rakudoc:Syndicate::Extensions>
to parse and generate C<media:content>, C<media:thumbnail>, C<media:title>,
and C<media:description> elements in RSS items.

Simply C<use> this module to activate:

=begin code :lang<raku>
use Syndicate::Extension::MediaRSS;
=end code

=head1 EXPORTED SUBS

=item C<get-media-text($parent, $tag)> - Get media:* text
=item C<get-media-contents($parent)> - Get media:content entries
=item C<get-media-thumbnails($parent)> - Get media:thumbnail entries
=item C<add-media-declaration(XML::Element)> - Add namespace declaration
=item C<add-media-content-element($parent, %content)> - Add media:content
=item C<add-media-thumbnail-element($parent, %thumb)> - Add media:thumbnail

=end pod
