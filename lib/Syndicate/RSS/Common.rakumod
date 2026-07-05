use v6.d;
use XML;
use Syndicate::Utils;

unit role Syndicate::RSS::Common:ver<0.0.1>:auth<zef:sasha>;

method !set-item-flags(Bool :$check-content = True) {
    my $dc     = False;
    my $media  = False;
    my $itunes = False;
    my $content = False;
    for self.items -> $item {
        $dc     ||= $item.?has-dc-creator;
        $media  ||= ?($item.?media-contents) || ?($item.?media-thumbnails) || $item.?media-title.defined || $item.?media-description.defined;
        $itunes ||= $item.?itunes-author.defined || $item.?itunes-summary.defined || $item.?itunes-duration.defined;
        $content ||= ?($item.?content.defined && $item.?content.chars) if $check-content;
        last if $dc && $media && $itunes && ($check-content ?? $content !! True);
    }
    ($dc, $media, $itunes, $content)
}

method parse-image($channel --> Hash) {
    my %image;
    with $channel.elements(:TAG<image>)[0] {
        %image<url>         = get-text-optional($_, "url");
        %image<title>       = get-text-optional($_, "title");
        %image<link>        = get-text-optional($_, "link");
        %image<width>       = get-text-optional($_, "width");
        %image<height>      = get-text-optional($_, "height");
        %image<description> = get-text-optional($_, "description");
    }
    %image
}

method !build-xml-elements($parent, %data, *@keys) {
    for @keys -> $key {
        with %data{$key} {
            $parent.append: XML::Element.new(:name($key), :nodes([encode-entities($_)])) if .chars;
        }
    }
}

method build-xml-image($parent, %image, Bool :$rdf-about = False) {
    return unless %image;
    my $img = XML::Element.new(:name<image>);
    $img.attribs{'rdf:about'} = %image<about> if $rdf-about && %image<about>.defined;
    self!build-xml-elements($img, %image, <url title link width height description>);
    $parent.append: $img;
}

method build-xml-textinput($parent, %textInput) {
    return unless %textInput;
    my $ti = XML::Element.new(:name<textinput>);
    self!build-xml-elements($ti, %textInput, <title description name link>);
    $parent.append: $ti;
}

method build-xml-skip-hours($parent, @skipHours) {
    return unless @skipHours;
    my $sh = XML::Element.new(:name<skipHours>);
    $sh.append: XML::Element.new(:name<hour>, :nodes([encode-entities(~$_)])) for @skipHours;
    $parent.append: $sh;
}

method build-xml-skip-days($parent, @skipDays) {
    return unless @skipDays;
    my $sd = XML::Element.new(:name<skipDays>);
    $sd.append: XML::Element.new(:name<day>, :nodes([encode-entities($_)])) for @skipDays;
    $parent.append: $sd;
}

=begin pod

=head1 NAME

Syndicate::RSS::Common - Shared role for RSS 2.0 and RSS 0.91

=head1 DESCRIPTION

Provides shared parsing and XML generation methods for image elements.
Used by both L<C<Syndicate::RSS>|rakudoc:Syndicate::RSS>
and L<C<Syndicate::RSS::V0_91>|rakudoc:Syndicate::RSS::V0_91>.

=head1 METHODS

=item C<parse-image($channel)> - Parse image element into Hash
=item C<build-xml-image($parent, %image, Bool :$rdf-about)> - Generate image XML

=end pod
