use v6.d;
use OO::Monitors;

unit monitor Syndicate::Stats:ver<0.0.1>:auth<zef:sasha>;

has atomicint $!feeds-parsed = 0;
has atomicint $!items-parsed = 0;
has atomicint $!errors = 0;

method feeds-parsed { $!feeds-parsed }
method items-parsed { $!items-parsed }
method errors { $!errors }

method record-feed { atomic-fetch-inc($!feeds-parsed) }
method record-item { atomic-fetch-inc($!items-parsed) }
method record-error { atomic-fetch-inc($!errors) }

=begin pod

=head1 NAME

Syndicate::Stats - Thread-safe statistics monitor

=head1 SYNOPSIS

=begin code :lang<raku>
use Syndicate::Config;
Syndicate::Stats.record-feed;
say Syndicate::Stats.feeds-parsed;
=end code

=head1 DESCRIPTION

A monitor (thread-safe) that tracks parsing statistics: feeds parsed,
items parsed, and error counts. Used internally. C<OO::Monitors> ensures
atomic operations.

=head1 METHODS

=item C<feeds-parsed> - Number of feeds parsed
=item C<items-parsed> - Number of items parsed
=item C<errors> - Number of parse errors
=item C<record-feed> - Increment feed counter
=item C<record-item> - Increment item counter
=item C<record-error> - Increment error counter

=end pod
