use v6.d;

unit role Syndicate::Feed:ver<0.0.1>:auth<zef:sasha>;

has Str $.title;
has Str $.link;
has Str $.description;
has @.items;
