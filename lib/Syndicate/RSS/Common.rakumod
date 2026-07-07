use v6.d;
use XML;
use Syndicate::Utils;
use Syndicate::Extension::ITunes;

my constant NS-CONTENT is export = 'http://purl.org/rss/1.0/modules/content/';

unit role Syndicate::RSS::Common:ver<0.0.1>:auth<zef:sasha>;

method parse-channel-common($channel --> Hash) {
    my %h;
    %h<title>   = get-text($channel, "title");
    %h<link>    = get-text($channel, "link");
    %h<desc>    = get-text($channel, "description");
    %h<lang>    = get-text-optional($channel, "language");
    %h<cpy>     = get-text-optional($channel, "copyright");
    %h<me>      = get-text-optional($channel, "managingEditor");
    %h<wm>      = get-text-optional($channel, "webMaster");
    %h<pd>      = parse-date-optional(get-text-optional($channel, "pubDate"));
    %h<lbd>     = parse-date-optional(get-text-optional($channel, "lastBuildDate"));
    %h<gen>     = get-text-optional($channel, "generator");
    %h<docs>    = get-text-optional($channel, "docs");
    %h<image>   = self.parse-image($channel);
    %h<it-author>  = get-itunes-text($channel, "author");
    %h<it-summary> = get-itunes-text($channel, "summary");
    %h
}

method parse-image($parent, Bool :$rdf-about = False --> Hash) {
    my %image;
    with $parent.elements(:TAG<image>)[0] {
        %image<url>         = get-text-optional($_, "url");
        %image<title>       = get-text-optional($_, "title");
        %image<link>        = get-text-optional($_, "link");
        my $w = get-text-optional($_, "width");
        my $h = get-text-optional($_, "height");
        %image<width>       = +$w if $w.defined;
        %image<height>      = +$h if $h.defined;
        %image<description> = get-text-optional($_, "description");
        %image<about>       = $_.attribs{'rdf:about'} // $_.attribs<about> // Str if $rdf-about;
    }
    %image
}

method !build-xml-elements($parent, %data, *@keys) {
    for @keys -> $key {
        with %data{$key} {
            # ~$_ stringifies the value; callers pass Str or Numeric values
            $parent.append: XML::Element.new(:name($key), :nodes([encode-entities(~$_)])) if ~$_.chars;
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
    my $ti = XML::Element.new(:name<textInput>);
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

Syndicate::RSS::Common - Shared role for RSS 2.0, RSS 0.91, and RSS 1.0

=head1 DESCRIPTION

Provides shared parsing and XML generation methods for image elements
and namespace-flag detection. Used by L<C<Syndicate::RSS>|rakudoc:Syndicate::RSS>,
L<C<Syndicate::RSS::V0_91>|rakudoc:Syndicate::RSS::V0_91>,
and L<C<Syndicate::RSS::V1_0>|rakudoc:Syndicate::RSS::V1_0>.

=head1 METHODS

=item C<parse-image($channel)> - Parse image element into Hash
=item C<build-xml-image($parent, %image, Bool :$rdf-about)> - Generate image XML

=end pod
