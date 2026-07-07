use v6.d;

unit class Syndicate::Stats:ver<0.0.1>:auth<zef:sasha>;

my atomicint $feeds-parsed = 0;
my atomicint $items-parsed = 0;
my atomicint $errors = 0;
submethod feeds-parsed { ⚛$feeds-parsed }
submethod items-parsed { ⚛$items-parsed }
submethod errors { ⚛$errors }

submethod record-feed { $feeds-parsed⚛++ }
submethod record-item { $items-parsed⚛++ }
submethod record-error { $errors⚛++ }

submethod reset {
    $feeds-parsed ⚛= 0;
    $items-parsed ⚛= 0;
    $errors ⚛= 0;
}

=begin pod

=head1 NAME

Syndicate::Stats - Thread-safe parsing statistics

=head1 SYNOPSIS

=begin code :lang<raku>
use Syndicate::Stats;
Syndicate::Stats.record-feed;
say Syndicate::Stats.feeds-parsed;
=end code

=head1 DESCRIPTION

Tracks parsing statistics: feeds parsed, items parsed, and error counts.
Uses class-scoped C<atomicint> counters for thread safety. Methods may be
called on the type object directly (no instantiation needed).

=head1 METHODS

=item C<feeds-parsed> - Number of feeds parsed
=item C<items-parsed> - Number of items parsed
=item C<errors> - Number of parse errors
=item C<record-feed> - Increment feed counter
=item C<record-item> - Increment item counter
=item C<record-error> - Increment error counter

=end pod
