use v6.d;
use XML;
use Syndicate::Extensions;
use Syndicate::Utils;

my constant NS-MEDIA is export = 'http://search.yahoo.com/mrss/';

unit module Syndicate::Extension::MediaRSS:ver<0.0.6>:auth<zef:sasha>;

register-ext(:namespace<media>, :namespace-uri(NS-MEDIA),
    parse => sub ($elem, %attrs) {
        # Single pass over direct children so contents/thumbnails/groups are
        # not scanned separately (and group contents are never double-counted).
        # Membership is namespace-aware (any prefix bound to the MRSS URI, or
        # an undeclared canonical 'media:' prefix) like the DC/ITunes helpers.
        my (@mc, @mt, @mg);
        my $has-media = False;
        for $elem.elements -> $e {
            next unless is-media-element($e);
            my $local = $e.name.contains(':') ?? $e.name.split(':')[1] !! $e.name;
            given $local {
                when 'content'   { @mc.push: media-content-of($e);   $has-media = True }
                when 'thumbnail' { @mt.push: media-thumbnail-of($e); $has-media = True }
                when 'group'     { with media-group-of($e) { @mg.push: $_; $has-media = True } }
            }
        }
        my $mt = get-media-text($elem, "title");
        my $md = get-media-text($elem, "description");
        return unless $has-media || $mt.defined || $md.defined;
        %attrs<media-contents> = @mc if @mc;
        %attrs<media-thumbnails> = @mt if @mt;
        %attrs<media-groups> = @mg if @mg;
        %attrs<media-title>       = $mt if $mt.defined;
        %attrs<media-description> = $md if $md.defined;
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
    with media-elements($parent, $tag)[0] -> $e {
        my $text = decode-entities(element-text($e)).trim;
        return $text.defined && $text.chars ?? $text !! Str;
    }
    Str
}

sub is-media-element(XML::Element $e --> Bool) is export {
    # Namespace-aware membership: the element resolves to the MRSS URI via
    # any declared prefix (in its own or an ancestor scope), or is a lenient
    # undeclared canonical 'media:'-prefixed element. A prefix bound to a
    # different URI is never a match.
    matches-ns($e, NS-MEDIA, 'media')
}

sub media-elements($parent, Str $local-name --> List) is export {
    my @matched;
    for $parent.elements -> $e {
        next unless is-media-element($e);
        my $name = $e.name;
        my $local = $name.contains(':') ?? $name.split(':')[1] !! $name;
        @matched.push: $e if $local eq $local-name;
    }
    @matched
}

sub media-numeric(Str $val --> Str) {
    # Always return the source string so to-hash/to-json emit uniform types
    # (matching enclosure-length's Str convention), rather than Int for
    # parseable values and raw Str otherwise.
    decode-entities($val)
}

sub media-content-of(XML::Element $e --> Hash) {
    my %c;
    %c<url>      = decode-entities($e.attribs<url>      // Str);
    %c<type>     = decode-entities($e.attribs<type>     // Str);
    %c<medium>   = decode-entities($e.attribs<medium>   // Str);
    %c<duration> = media-numeric($e.attribs<duration> // Str) if $e.attribs<duration>.defined;
    %c<fileSize> = media-numeric($e.attribs<fileSize> // Str) if $e.attribs<fileSize>.defined;
    %c<width>    = media-numeric($e.attribs<width>    // Str) if $e.attribs<width>.defined;
    %c<height>   = media-numeric($e.attribs<height>   // Str) if $e.attribs<height>.defined;
    # Mirror the generate side: a nested media:title/media:description inside
    # this content round-trips back to the content hash, not the item level.
    my $title = get-media-text($e, "title");
    my $desc  = get-media-text($e, "description");
    %c<title>       = $title if $title.defined && $title.chars;
    %c<description> = $desc  if $desc.defined && $desc.chars;
    %c
}

sub media-thumbnail-of(XML::Element $e --> Hash) {
    my %t;
    %t<url>    = decode-entities($e.attribs<url>    // Str);
    %t<width>  = media-numeric($e.attribs<width> // Str) if $e.attribs<width>.defined;
    %t<height> = media-numeric($e.attribs<height> // Str) if $e.attribs<height>.defined;
    %t<time>   = decode-entities($e.attribs<time>    // Str);
    %t
}

sub media-group-of(XML::Element $g) {
    my (@gc, @gt);
    for $g.elements -> $e {
        next unless is-media-element($e);
        my $local = $e.name.contains(':') ?? $e.name.split(':')[1] !! $e.name;
        if $local eq 'content'   { @gc.push: media-content-of($e) }
        elsif $local eq 'thumbnail' { @gt.push: media-thumbnail-of($e) }
    }
    return unless @gc || @gt;
    my %group;
    %group<media-contents>   = @gc if @gc;
    %group<media-thumbnails> = @gt if @gt;
    %group
}

sub get-media-contents($parent --> Array) is export {
    my @contents;
    for media-elements($parent, 'content') -> $e {
        @contents.push: media-content-of($e);
    }
    @contents
}

sub get-media-thumbnails($parent --> Array) is export {
    my @thumbs;
    for media-elements($parent, 'thumbnail') -> $e {
        @thumbs.push: media-thumbnail-of($e);
    }
    @thumbs
}

sub get-media-groups($parent --> Array) is export {
    my @groups;
    for media-elements($parent, 'group') -> $g {
        with media-group-of($g) { @groups.push: $_ }
    }
    @groups
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
    # MRSS allows media:title/media:description inside media:content (per
    # content, not just per item); emit them nested so each content keeps its
    # own metadata instead of collapsing everything to the item level.
    $e.append: XML::Element.new(:name<media:title>, :nodes([encode-entities(~%content<title>)]))
        if %content<title>.defined && %content<title>.chars;
    $e.append: XML::Element.new(:name<media:description>, :nodes([encode-entities(~%content<description>)]))
        if %content<description>.defined && %content<description>.chars;
    $parent.append: $e;
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
