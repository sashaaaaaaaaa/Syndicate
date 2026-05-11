use v6.d;
use XML;
use Syndicate::Item;

unit class Syndicate::RSS::V0_91::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

method XML {
    my $xml = XML::Element.new(:name<item>);
    $xml.append: XML::Element.new(:name<title>, :nodes([$.title])) if $.title.defined;
    $xml.append: XML::Element.new(:name<link>, :nodes([$.link])) if $.link.defined;
    $xml.append: XML::Element.new(:name<description>, :nodes([$.summary])) if $.summary.defined;
    $xml
}

method Str(Bool :$pretty = True) { ~self.XML }

=begin pod

=head1 NAME

Syndicate::RSS::V0_91::Item - RSS 0.91 item

=head1 DESCRIPTION

An RSS 0.91 item. Does L<C<Syndicate::Item>|rakudoc:Syndicate::Item>.
Only supports title, link, and description — no metadata fields.

=end pod
