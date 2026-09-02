use v6.d;
use XML;
use Syndicate::Utils;
use Syndicate::Extension::ITunes;
use Syndicate::Stats;

my constant NS-CONTENT is export = 'http://purl.org/rss/1.0/modules/content/';
my constant NS-RDF     is export = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';

unit role Syndicate::RSS::Common:ver<0.0.4>:auth<zef:sasha>;

has XML::Element $!cached-xml;
has Lock $!xml-lock = Lock.new;
has Bool $!needs-dc is built;
has Bool $!needs-media is built;
has Bool $!needs-content is built;
has Bool $!needs-itunes is built;

method !type-name { "RSS" }

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    unless $doc {
        Syndicate::Stats.record-error;
        die "Invalid {self!type-name} XML: $!";
    }
    self.new($doc)
}

method XML {
    return $!cached-xml if $!cached-xml.defined;
    $!xml-lock.protect: {
        return $!cached-xml if $!cached-xml.defined;
        $!cached-xml = self!build-xml
    }
}

method !apply-item-needs(@items, $itunes-author, $itunes-summary --> Nil) {
    my %needs = compute-needs(@items);
    $!needs-dc      ||= %needs<dc>;
    $!needs-media   ||= %needs<media>;
    $!needs-content ||= %needs<content>;
    $!needs-itunes  ||= %needs<itunes> || $itunes-author.defined || $itunes-summary.defined;
}

method parse-channel-common($channel --> Hash) {
    my %h;
    %h<title>             = get-text($channel, "title");
    %h<link>              = get-text($channel, "link");
    %h<description>       = get-text($channel, "description");
    %h<language>          = get-text-optional($channel, "language");
    %h<copyright>         = get-text-optional($channel, "copyright");
    %h<managing-editor>   = get-text-optional($channel, "managingEditor");
    %h<web-master>        = get-text-optional($channel, "webMaster");
    %h<pub-date>          = parse-date(:optional, get-text-optional($channel, "pubDate"));
    %h<last-build-date>   = parse-date(:optional, get-text-optional($channel, "lastBuildDate"));
    %h<generator>         = get-text-optional($channel, "generator");
    %h<docs>              = get-text-optional($channel, "docs");
    %h<itunes-author>     = get-itunes-text($channel, "author");
    %h<itunes-summary>    = get-itunes-text($channel, "summary");
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
        my $wn = $w.defined ?? try +$w !! Any;
        my $hn = $h.defined ?? try +$h !! Any;
        %image<width>       = $wn if $wn.defined;
        %image<height>      = $hn if $hn.defined;
        %image<description> = get-text-optional($_, "description");
        %image<about>       = decode-entities($_.attribs{'rdf:about'} // $_.attribs<about> // Str) if $rdf-about;
    }
    %image
}

method !build-xml-elements($parent, %data, *@keys) {
    for @keys -> $key {
        with %data{$key} {
            # ~$_ stringifies the value; callers pass Str or Numeric values
            $parent.append: XML::Element.new(:name($key), :nodes([encode-entities(~$_)])) if ~$_;
        }
    }
}

method build-xml-image($parent, %image, Bool :$rdf-about = False) {
    return unless %image;
    my $img = XML::Element.new(:name<image>);
    add-attrib($img, 'rdf:about', %image<about>) if $rdf-about && %image<about>.defined;
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

Provides shared parsing and XML generation methods for image elements,
namespace-flag detection, and the cached XML construction machinery
used by L<C<Syndicate::RSS>|rakudoc:Syndicate::RSS>,
L<C<Syndicate::RSS::V0_91>|rakudoc:Syndicate::RSS::V0_91>,
and L<C<Syndicate::RSS::V1_0>|rakudoc:Syndicate::RSS::V1_0>.

The role declares the private C<$!cached-xml>, C<$!xml-lock>, and
C<$!needs-dc/media/content/itunes> attributes, provides the string
constructor C<new(Str $xml)> and the lock-guarded C<XML> method (which
delegates per-format element construction to the consuming class's
private C<!build-xml> method), and factors the item-driven namespace
flag computation into C<!apply-item-needs>.

=head1 METHODS

=item C<parse-channel-common($channel)> - Parse shared channel fields into Hash
=item C<parse-image($parent, Bool :$rdf-about)> - Parse image element into Hash
=item C<build-xml-image($parent, %image, Bool :$rdf-about)> - Generate image XML
=item C<build-xml-textinput($parent, %textInput)> - Generate textInput XML
=item C<build-xml-skip-hours($parent, @skipHours)> - Generate skipHours XML
=item C<build-xml-skip-days($parent, @skipDays)> - Generate skipDays XML
=item C<new(Str $xml)> - Parse feed XML string (message uses C<!type-name>)
=item C<XML> - Returns the cached L<C<XML::Element>|rakudoc:XML::Element>

=end pod
