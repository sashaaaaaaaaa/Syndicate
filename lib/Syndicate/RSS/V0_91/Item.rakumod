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

method Str { ~self.XML }
