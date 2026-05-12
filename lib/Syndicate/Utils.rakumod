use v6.d;
use XML;
use DateTime::Grammar;

unit module Syndicate::Utils:ver<0.0.1>:auth<zef:sasha>;

# Per-call XML::Entity.new is intentional — XML::Entity's thread-safety
# is undocumented, so constructing per call avoids shared-state races.
sub decode-entities(Str $text) is export {
    return $text unless $text.defined && $text.chars;
    XML::Entity.new.decode($text)
}

sub encode-entities(Str $text) is export {
    return $text unless $text.defined && $text.chars;
    XML::Entity.new.encode($text)
}

sub get-text($parent, $tag) is export {
    with $parent.elements(:TAG($tag))[0] -> $e {
        with $e.contents[0] -> $t {
            return decode-entities($t.text // "");
        }
    }
    Str
}

sub get-text-optional($parent, $tag) is export {
    with $parent.elements(:TAG($tag))[0] -> $e {
        with $e.contents[0] -> $t {
            my $text = $t.text;
            return $text.chars ?? decode-entities($text) !! Str;
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

=begin pod

=head1 NAME

Syndicate::Utils - Internal utility functions

=head1 DESCRIPTION

Shared helper functions used by parser/generator classes.
Not typically needed by end users.

=head1 EXPORTED SUBS

=item C<decode-entities(Str)>, C<encode-entities(Str)> - XML entity handling
=item C<get-text($parent, $tag)> - Get required text content of a child element
=item C<get-text-optional($parent, $tag)> - Get optional text content (returns C<Str>)
=item C<get-attrib($parent, $tag, $attr)> - Get an attribute value from a child element
=item C<parse-date(Str)> - Parse date string returning C<DateTime> or C<Nil>
=item C<parse-date-optional(Str)> - Parse date string returning C<DateTime> or C<Str>

=end pod
