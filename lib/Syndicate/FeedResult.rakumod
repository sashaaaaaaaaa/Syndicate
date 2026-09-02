use v6.d;
use Syndicate::Format;
use Syndicate::Feed;

unit class Syndicate::FeedResult:ver<0.0.6>:auth<zef:sasha>;

has FeedFormat $.format;
has Syndicate::Feed $.feed;

=begin pod

=head1 NAME

Syndicate::FeedResult - Format and feed pair returned by C<parse-feed-with-format>

=head1 DESCRIPTION

A small typed record holding the detected L<C<FeedFormat>|rakudoc:Syndicate::Format>
and the parsed L<C<Syndicate::Feed>|rakudoc:Syndicate::Feed>. Returned by
C<parse-feed-with-format> so callers get both the format and the feed from a
single parse pass without destructuring a bare C<List>.

=head1 ATTRIBUTES

=item C<$.format> - The detected L<C<FeedFormat>|rakudoc:Syndicate::Format>
=item C<$.feed> - The parsed L<C<Syndicate::Feed>|rakudoc:Syndicate::Feed> object

=end pod
