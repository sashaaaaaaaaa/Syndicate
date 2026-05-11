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
