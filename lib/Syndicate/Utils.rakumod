use v6.d;
use XML;
use XML::Entity;
use DateTime::Grammar;
use DateTime::Format::RFC2822;

my constant NS-ATOM is export = 'http://www.w3.org/2005/Atom';
my constant %TZ-OFFSET = (
    'EST'  => '-0500', 'EDT'  => '-0400',
    'CST'  => '-0600', 'CDT'  => '-0500',
    'MST'  => '-0700', 'MDT'  => '-0600',
    'PST'  => '-0800', 'PDT'  => '-0700',
    'CET'  => '+0100', 'CEST' => '+0200',
    'EET'  => '+0200', 'EEST' => '+0300',
    'IST'  => '+0530', 'HKT'  => '+0800',
    'JST'  => '+0900', 'AEST' => '+1000',
    'AEDT' => '+1100', 'NZST' => '+1200',
    'NZDT' => '+1300',
);

unit module Syndicate::Utils:ver<0.0.1>:auth<zef:sasha>;

my constant $XML-ENTITY = XML::Entity.new;
my constant RFC2822-FORMAT is export = DateTime::Format::RFC2822.new;

sub decode-entities(Str $text --> Str) is export {
    return $text unless $text.defined && $text.chars;
    $XML-ENTITY.decode($text)
}

sub encode-entities(Str $text --> Str) is export {
    return $text unless $text.defined && $text.chars;
    $XML-ENTITY.encode($text)
}

sub add-element($parent, $name, $value --> Nil) is export {
    return unless $value.defined;
    $parent.append: XML::Element.new(:name($name), :nodes([encode-entities($value)]));
}

sub add-attrib($elem, $name, $value --> Nil) is export {
    return unless $value.defined;
    $elem.attribs{$name} = encode-entities($value);
}

proto sub node-text($node --> Str) is export {*}
multi sub node-text(XML::Text $n)    { $n.text }
multi sub node-text(XML::CDATA $n)   { $n.data }
multi sub node-text(XML::Element $n) { $n.nodes.map(&node-text).join }
multi sub node-text($n)              { "" }

sub element-text($e --> Str) is export { $e.nodes.map(&node-text).join }

sub get-text($parent, $tag --> Str) is export {
    my $e = $parent.elements(:TAG($tag))[0];
    die "Missing required element <$tag> in <{$parent.name}>" without $e;
    my $text = element-text($e).trim;
    die "Empty required element <$tag> in <{$parent.name}>" unless $text.chars;
    return decode-entities($text);
}

sub text-of-optional($e --> Str) {
    my $text = element-text($e).trim;
    $text.chars ?? decode-entities($text) !! Str
}

sub get-text-optional($parent, $tag --> Str) is export {
    # Note: Returns Str (type object) for both "element missing" and
    # "element empty". Use .defined to distinguish from a found value.
    my $e = $parent.elements(:TAG($tag))[0];
    $e.defined ?? text-of-optional($e) !! Str
}

sub get-text-by-ns($parent, $local-name, $ns-uri --> Str) is export {
    my $e = $parent.elements(:TAG($local-name), :namespace($ns-uri))[0];
    $e.defined ?? text-of-optional($e) !! Str
}

sub parse-categories($parent --> Array) is export {
    my @categories;
    for $parent.elements(:TAG<category>) -> $c {
        my $text = element-text($c).trim;
        @categories.push: decode-entities($text) if $text.chars;
    }
    @categories
}

sub normalize-date-str(Str $str --> Str) {
    my $s = $str;
    $s .= subst(/ (\d ** 1..2) ':' (\d ** 2) ':' (\d ** 2) \s* (:i <[PA]>M) /, -> $/ {
        my $h = +$0;
        if ~$3.lc eq 'am' { $h = 0 if $h == 12 }
        else              { $h += 12 if $h < 12 }
        sprintf "%02d:%02d:%02d", $h, +$1, +$2;
    });
    $s .= subst(/ (\d ** 1..2) ':' (\d ** 2) \s* (:i <[PA]>M) /, -> $/ {
        my $h = +$0;
        if ~$2.lc eq 'am' { $h = 0 if $h == 12 }
        else              { $h += 12 if $h < 12 }
        sprintf "%02d:%02d:%02d", $h, +$1, 0;
    });
    $s .= subst(:g, /
        << EST >> | << EDT >> | << CST >> | << CDT >> |
        << MST >> | << MDT >> | << PST >> | << PDT >> |
        << CET >> | << CEST >> | << EET >> | << EEST >> |
        << IST >> | << HKT >> | << JST >> |
        << AEST >> | << AEDT >> | << NZST >> | << NZDT >>
    /, {
        %TZ-OFFSET{~$/}
    });
    $s
}

sub parse-date(Str $str --> DateTime) is export {
    die "parse-date: empty or unset string" unless $str.defined && $str.trim.chars > 0;
    my $normalized = normalize-date-str($str.trim);
    datetime-interpret($normalized) // die "parse-date: cannot parse '$str'"
}

sub parse-date-optional(Any $str) is export {
    return Nil unless $str.defined && $str.Str.trim.chars > 0;
    my $normalized = normalize-date-str($str.Str.trim);
    datetime-interpret($normalized) // Nil
}

sub compute-needs(@items --> Hash) is export {
    my Bool ($needs-dc, $needs-media, $needs-itunes, $needs-content) = False xx 4;
    for @items -> $item {
        my %nf = $item.?namespace-flags // %();
        $needs-dc      ||= ?%nf<dc>;
        $needs-media   ||= ?%nf<media>;
        $needs-itunes  ||= ?%nf<itunes>;
        $needs-content ||= ?%nf<content>;
    }
    %(:dc($needs-dc), :media($needs-media), :itunes($needs-itunes), :content($needs-content))
}

=begin pod

=head1 NAME

Syndicate::Utils - Internal utility functions

=head1 DESCRIPTION

Shared helper functions used by parser/generator classes.
Not typically needed by end users.

=head1 EXPORTED SUBS

=item C<decode-entities(Str)>, C<encode-entities(Str)> - XML entity handling
=item C<get-text($parent, $tag)> - Get required text content, dies if element missing
=item C<get-text-optional($parent, $tag)> - Get optional text content (returns C<Str>)
=item C<parse-categories($parent)> - Extract category tags text content
=item C<parse-date(Str)> - Parse date string, dies on bad input, returns C<DateTime>
=item C<parse-date-optional(Str)> - Parse date string returning C<DateTime> or C<Nil>

=end pod
