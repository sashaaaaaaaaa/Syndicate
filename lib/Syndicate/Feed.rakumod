use v6.d;
use Syndicate::Item;

unit role Syndicate::Feed:ver<0.0.1>:auth<zef:sasha>;

has Str $.title;
has Str $.link;
has Str $.description;
has Str $.generator;
has Str $.language;
has @!items of Syndicate::Item is built;
method items() { @!items.List }
has Str $!cached-str;
has Lock $!cache-lock = Lock.new;

method Str {
    $!cache-lock.protect: {
        $!cached-str //= '<?xml version="1.0" encoding="UTF-8"?>' ~ "\n" ~ self.XML.Str
    }
}

=begin pod

=head1 NAME

Syndicate::Feed - Common feed role

=head1 DESCRIPTION

All feed types (RSS, Atom, JSONFeed) do this role, providing a uniform
interface for accessing common feed metadata.

=head1 ATTRIBUTES

=item C<$.title> - Feed title
=item C<$.link> - Feed link/home page URL
=item C<$.description> - Feed description/subtitle
=item C<$.generator> - Generator name (e.g., "Syndicate")
=item C<$.language> - Feed language code (e.g., "en")
=item C<@.items> - Array of L<C<Syndicate::Item>|rakudoc:Syndicate::Item> objects

=end pod
