use v6.d;
use XML;
use XML::Entity;
use DateTime::Grammar;

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

my $entity = XML::Entity.new;
my $entity-lock = Lock.new;

sub decode-entities(Str $text --> Str) is export {
    return $text unless $text.defined && $text.chars;
    $entity-lock.protect: { $entity.decode($text) }
}

sub encode-entities(Str $text --> Str) is export {
    return $text unless $text.defined && $text.chars;
    $entity-lock.protect: { $entity.encode($text) }
}

sub add-element($parent, $name, $value --> Nil) is export {
    return unless $value.defined;
    $parent.append: XML::Element.new(:name($name), :nodes([encode-entities($value)]));
}

sub get-text($parent, $tag --> Str) is export {
    my $e = $parent.elements(:TAG($tag))[0];
    die "Missing required element <$tag>" without $e;
    with $e.contents[0] -> $t {
        my $text = ($t.?text // "").trim;
        die "Empty required element <$tag>" unless $text.chars;
        return decode-entities($text);
    }
    die "Element <$tag> has no child nodes"
}

sub get-text-optional($parent, $tag --> Str) is export {
    # Note: Returns Str (type object) for both "element missing" and
    # "element empty". Use .defined to distinguish from a found value.
    with $parent.elements(:TAG($tag))[0] -> $e {
        with $e.contents[0] -> $t {
            my $text = ($t.?text // "").trim;
            return $text.defined && $text.chars ?? decode-entities($text) !! Str;
        }
    }
    Str
}

sub get-text-by-ns($parent, $local-name, $ns-uri --> Str) is export {
    my $e = $parent.elements(:TAG($local-name), :namespace($ns-uri))[0];
    with $e {
        with $e.contents[0] -> $t {
            my $text = ($t.?text // "").trim;
            return $text.defined && $text.chars ?? decode-entities($text) !! Str;
        }
    }
    Str
}

sub parse-categories($parent --> Array) is export {
    my @categories;
    for $parent.elements(:TAG<category>) -> $c {
        with $c.contents[0] -> $t {
            my $text = $t.?text // "";
            @categories.push: decode-entities($text) if $text.chars;
        }
    }
    @categories
}

sub normalize-date-str(Str $str --> Str) {
    my $s = $str;
    $s .= subst(/ (\d ** 1..2) ':' (\d ** 2) ':' (\d ** 2) \s* (<[PA]>M) /, -> $/ {
        my $h = +$0;
        if ~$3 eq 'AM' { $h = 0 if $h == 12 }
        else           { $h += 12 if $h < 12 }
        sprintf "%02d:%02d:%02d", $h, +$1, +$2;
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

sub parse-date-optional(Str $str) is export {
    return Nil unless $str.defined && $str.trim.chars > 0;
    my $normalized = normalize-date-str($str.trim);
    datetime-interpret($normalized) // Nil
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
