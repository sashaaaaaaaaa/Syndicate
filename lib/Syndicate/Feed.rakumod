use v6.d;
use Syndicate::Item;
use Syndicate::Utils;

unit role Syndicate::Feed:ver<0.0.3>:auth<zef:sasha>;

has Str $.title;
has Str $.link;
has Str $.description;
has Str $.generator;
has Str $.language;
has @!items of Syndicate::Item is built;
method items() { @!items.List }
# Caches assume the feed object is immutable after construction.
# Any mutation to attributes after the first call to .Str or .to-hash
# will not be reflected in the cached output.
has Str $!cached-str;
has Str $!cached-pretty-str;
has Lock $!cache-lock = Lock.new;
# Item hashes are built once and deep-cloned on every call so callers can
# never mutate the cache (see sanitize), mirroring the JSONFeed cache.
has $!cached-item-hashes;

method to-hash(:$clone = True) {
    self.to-hash-common(:$clone)
}

method to-hash-common(:$clone = True) {
    my %h;
    %h<title>       = $.title       if $.title.defined;
    %h<link>        = $.link        if $.link.defined;
    %h<description> = $.description if $.description.defined;
    %h<generator>   = $.generator   if $.generator.defined;
    %h<language>    = $.language    if $.language.defined;
    if @!items {
        # Guarded by the cache lock so concurrent to-hash calls never race
        # the lazy build (the write is idempotent, but this matches the
        # lock-discipline of Str/JSONFeed).
        $!cache-lock.protect: {
            $!cached-item-hashes //= @!items.map(*.to-hash).Array;
        }
        # Cloned per call so callers can never mutate the cache (see
        # sanitize); :!clone opts out of the O(items) copy for hot paths.
        %h<items> = $clone
            ?? $!cached-item-hashes.map({ sanitize($_) }).Array
            !! $!cached-item-hashes;
    }
    %h
}

method Str {
    $!cached-str // $!cache-lock.protect: {
        $!cached-str //= '<?xml version="1.0" encoding="UTF-8"?>' ~ "\n" ~ self.XML.Str
    }
}

# Stringify the feed, optionally with human-friendly indentation. The default
# (C<Str> / C<str()> without C<:pretty>) is unchanged: one line, maximum
# byte-compactness, matching the pre-existing behaviour. With C<:pretty> the
# XML is re-indented via L<C<indent-xml>|rakudoc:Syndicate::Utils>: the XML
# declaration stays on its own line and each element is indented two spaces per
# nesting level. Pretty output is derived from the cached compact C<Str>, so
# removing all whitespace from it yields exactly the compact form: the two
# differ only by inserted whitespace and parse identically.
method str(:$pretty = False) {
    $pretty ?? self!pretty-str !! self.Str
}

method !pretty-str {
    $!cached-pretty-str // $!cache-lock.protect: {
        # Derive from the cached compact Str (not a fresh XML serialization) so
        # plain/pretty are guaranteed to differ only by inserted whitespace,
        # even though XML::Element serializes attribute order non-deterministically.
        $!cached-pretty-str //= indent-xml(self.Str)
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

=head1 METHODS

=item C<Str> - Compact, single-line XML (declaration on its own line followed by the root element on one line). Back-compatible.
=item C<str(:$pretty = False)> - C<Str> when C<:pretty> is falsy; otherwise the XML with two-space indentation per nesting level via C<indent-xml>. Whitespace-only differences, so both forms parse identically.

=end pod
