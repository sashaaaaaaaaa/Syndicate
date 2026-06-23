use v6.d;
use XML;
use Syndicate::Item;
use Syndicate::Utils;
use Syndicate::Stats;

unit class Syndicate::RSS::V0_91::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

proto method new-from-xml(|) {*}
multi method new-from-xml(XML::Element $item-elem) {
    my $title = get-text-optional($item-elem, "title");
    my $link  = get-text-optional($item-elem, "link");
    my $desc  = get-text-optional($item-elem, "description");
    Syndicate::Stats.record-item;
    self.bless(:$title, :$link, :summary($desc), :id($link // Str), :content($desc // Str))
}

method XML {
    my $xml = XML::Element.new(:name<item>);
    $xml.append: XML::Element.new(:name<title>, :nodes([encode-entities($.title)])) if $.title.defined;
    $xml.append: XML::Element.new(:name<link>, :nodes([encode-entities($.link)])) if $.link.defined;
    $xml.append: XML::Element.new(:name<description>, :nodes([encode-entities($.summary)])) if $.summary.defined;
    $xml
}

method Str { ~self.XML }

=begin pod

=head1 NAME

Syndicate::RSS::V0_91::Item - RSS 0.91 item

=head1 DESCRIPTION

An RSS 0.91 item. Does L<C<Syndicate::Item>|rakudoc:Syndicate::Item>.
Only supports title, link, and description — no metadata fields.

=end pod
