use v6.d;

unit module Syndicate::Extensions:ver<0.0.1>:auth<zef:sasha>;

my @extensions;

sub register-ext(:&parse, :&generate) is export {
    @extensions.push: %(:&parse, :&generate)
}

sub run-parsers($elem, %attrs) is export {
    return unless @extensions;
    .<parse>($elem, %attrs) for @extensions;
}

sub run-generators($xml, $item) is export {
    return unless @extensions;
    .<generate>($xml, $item) for @extensions;
}

=begin pod

=head1 NAME

Syndicate::Extensions - Extension registration registry

=head1 DESCRIPTION

Central registry for feed format extensions. Extensions register
parse/generate callbacks that run automatically during RSS item
parsing and XML generation.

=head1 EXPORTED SUBS

=head2 C<register-ext(:&parse, :&generate)>

Register an extension. C<&parse> receives an XML::Element and a mutable
hash of attributes. C<&generate> receives an XML::Element and the item
object.

=head2 C<run-parsers($elem, %attrs)>

Runs all registered parse callbacks. Called during RSS item parsing.

=head2 C<run-generators($xml, $item)>

Runs all registered generate callbacks. Called during RSS item XML output.

=end pod
