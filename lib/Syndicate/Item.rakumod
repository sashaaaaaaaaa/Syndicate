use v6.d;

unit role Syndicate::Item:ver<0.0.1>:auth<zef:sasha>;

has Str $.title;
has Str $.link;
has Str $.summary;
has Str $.author;
has DateTime $.updated;
has Str $.id;
has Str $.content;

=begin pod

=head1 NAME

Syndicate::Item - Common item/entry role

=head1 DESCRIPTION

All item types (RSS, Atom, JSONFeed) do this role, providing a uniform
interface for accessing common entry metadata.

=head1 ATTRIBUTES

=item C<$.title> - Entry title
=item C<$.link> - Entry link/URL
=item C<$.summary> - Entry summary/description
=item C<$.author> - Entry author name
=item C<$.updated> - Last updated timestamp (L<C<DateTime>|rakudoc:DateTime>)
=item C<$.id> - Entry unique identifier
=item C<$.content> - Entry content body

=end pod
