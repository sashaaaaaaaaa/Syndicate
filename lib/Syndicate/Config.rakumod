use v6.d;
use OO::Monitors;

unit monitor Syndicate::Config:ver<0.0.1>:auth<zef:sasha>;

has int $!feeds-parsed = 0;
has int $!items-parsed = 0;
has int $!errors = 0;

method feeds-parsed { $!feeds-parsed }
method items-parsed { $!items-parsed }
method errors { $!errors }

method record-feed { ++$!feeds-parsed }
method record-item { ++$!items-parsed }
method record-error { ++$!errors }

=begin pod

=head1 NAME

Syndicate::Config - Thread-safe configuration monitor

=head1 SYNOPSIS

=begin code :lang<raku>
use Syndicate::Config;
Syndicate::Config.record-feed;
say Syndicate::Config.feeds-parsed;
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
