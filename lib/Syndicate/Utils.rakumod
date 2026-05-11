use v6.d;
use XML;
use DateTime::Grammar;

unit module Syndicate::Utils:ver<0.0.1>:auth<zef:sasha>;

sub get-text($parent, $tag) is export {
    with $parent.elements(:TAG($tag))[0] -> $e {
        with $e.contents[0] -> $t {
            return $t.text // "";
        }
    }
    ""
}

sub get-text-optional($parent, $tag) is export {
    with $parent.elements(:TAG($tag))[0] -> $e {
        with $e.contents[0] -> $t {
            my $text = $t.text;
            return $text.chars ?? $text !! Str;
        }
    }
    Str
}

sub get-attrib($parent, $tag, $attr) is export {
    with $parent.elements(:TAG($tag))[0] -> $e {
        my $a = $e.attribs{$attr} // Str;
        return $a;
    }
    Str
}

sub parse-date(Str $str) is export {
    return Nil unless $str.defined && $str.trim.chars > 0;
    try { datetime-interpret($str.trim) } // Nil
}

sub parse-date-optional(Str $str) is export {
    return Str unless $str.defined && $str.trim.chars > 0;
    try { datetime-interpret($str.trim) } // Str
}
