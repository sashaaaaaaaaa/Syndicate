use v6.d;

unit module Syndicate::Extensions:ver<0.0.1>:auth<zef:sasha>;

my @extensions;

sub register-ext(:&parse, :&generate) is export {
    @extensions.push: %(:&parse, :&generate)
}

sub run-parsers($elem, %attrs) is export {
    .<parse>($elem, %attrs) for @extensions
}

sub run-generators($xml, $item) is export {
    .<generate>($xml, $item) for @extensions
}
