use v6.d;

unit module Syndicate::Format:ver<0.0.4>:auth<zef:sasha>;

# The set of feed formats Syndicate can detect, parse, and generate.
enum FeedFormat is export <Atom RSS2 RSS091 RSS1 JSONFeedFmt>;

=begin pod

=head1 NAME

Syndicate::Format - Feed format enum

=head1 DESCRIPTION

Defines the L<C<FeedFormat>|rakudoc:Syndicate::Format> enum enumerating the
feed formats Syndicate supports: C<Atom>, C<RSS2>, C<RSS091>, C<RSS1>, and
C<JSONFeedFmt>. Split out from L<C<Syndicate::Parse>|rakudoc:Syndicate::Parse>
so it can be referenced without a circular module dependency.

=head1 ENUM C<FeedFormat>

=item C<Atom> - Atom 1.0
=item C<RSS2> - RSS 2.0
=item C<RSS091> - RSS 0.91
=item C<RSS1> - RSS 1.0
=item C<JSONFeedFmt> - JSON Feed

=end pod
