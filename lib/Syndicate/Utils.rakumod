use v6.d;
use XML::Entity;
use DateTime::Grammar;

unit module Syndicate::Utils:ver<0.0.1>:auth<zef:sasha>;

my $entity = XML::Entity.new;

sub decode-entities(Str $text) is export {
    return $text unless $text.defined && $text.chars;
    $entity.decode($text)
}

sub encode-entities(Str $text) is export {
    return $text unless $text.defined && $text.chars;
    $entity.encode($text)
}

sub get-text($parent, $tag) is export {
    my $e = $parent.elements(:TAG($tag))[0];
    die "Missing required element <$tag>" without $e;
    with $e.contents[0] -> $t {
        my $text = $t.?text // "";
        die "Empty required element <$tag>" unless $text.chars;
        return decode-entities($text);
    }
    die "Empty required element <$tag>"
}

sub get-text-optional($parent, $tag) is export {
    with $parent.elements(:TAG($tag))[0] -> $e {
        with $e.contents[0] -> $t {
            my $text = $t.?text // Str;
            return $text.defined && $text.chars ?? decode-entities($text) !! Str;
        }
    }
    Str
}

sub parse-datetime(Str $str) is export {
    datetime-interpret($str)
}

sub parse-date(Str $str) is export {
    die "Cannot parse date: empty or unset string" unless $str.defined && $str.trim.chars > 0;
    parse-datetime($str.trim) // die "Cannot parse date: $str"
}

sub parse-date-optional(Str $str) is export {
    return Nil unless $str.defined && $str.trim.chars > 0;
    parse-datetime($str.trim) // Nil
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
=item C<parse-date(Str)> - Parse date string, dies on bad input, returns C<DateTime>
=item C<parse-date-optional(Str)> - Parse date string returning C<DateTime> or C<Nil>

=end pod
