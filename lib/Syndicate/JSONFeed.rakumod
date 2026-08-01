use v6.d;
use JSON::Fast;
use Syndicate::Feed;
use Syndicate::JSONFeed::Item;
use Syndicate::Utils;
use Syndicate::Stats;

my constant JSONFEED-VERSION       is export = 'https://jsonfeed.org/version/1.1';
our constant JSONFEED-VERSION-PREFIX is export = 'https://jsonfeed.org/version/';

unit class Syndicate::JSONFeed:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed;

has Str $.version = JSONFEED-VERSION;
has Str $.feed_url;
has Str $.user_comment;
has Str $.next_url;
has Str $.icon;
has Str $.favicon;
has %.author of Str;
has Bool $.expired;
has Hash $!cached-hash;
has Lock $!hash-lock = Lock.new;
has Str $!cached-json;
has Lock $!json-lock = Lock.new;

multi method new(Str $json) {
    my %h;
    my $ok = try { %h = from-json($json); True };
    unless $ok {
        Syndicate::Stats.record-error;
        die "Invalid JSON: $!";
    }
    self.new-from-hash(%h)
}

multi method new-from-hash(%h) {
    with-error-recording {
        my $version = %h<version> // JSONFEED-VERSION;
        die "Invalid JSON Feed version: $version"
            unless $version.starts-with(JSONFEED-VERSION-PREFIX) && $version.chars > JSONFEED-VERSION-PREFIX.chars;
        my $title       = %h<title> // Str;
        die "JSON Feed requires title" unless $title.defined && $title.chars;
        my $link        = %h<home_page_url> // Str;
        my $desc        = %h<description> // Str;
        my $gen         = %h<generator> // Str;

        my %author;
        if %h<author> ~~ Hash {
            with %h<author> {
                %author<name>   = .<name> // Str;
                %author<url>    = .<url> // Str;
                %author<avatar> = .<avatar> // Str;
            }
        } elsif %h<author>.defined {
            die "JSON Feed 'author' must be a Hash, got {%h<author>.^name}";
        }

        my @items;
        die "JSON Feed requires 'items' key" unless %h<items>:exists;
        die "JSON Feed 'items' must be an array" unless %h<items> ~~ Array;
        for @(%h<items>) -> $item-data {
            die "JSON Feed 'items' must contain objects, got: {$item-data.^name}" unless $item-data ~~ Hash;
            @items.push: Syndicate::JSONFeed::Item.new-from-hash(%$item-data);
        }

        my %bless = :$version, :$title, :$link, :description($desc),
            :generator($gen),
            :feed_url(%h<feed_url> // Str),
            :user_comment(%h<user_comment> // Str),
            :next_url(%h<next_url> // Str),
            :icon(%h<icon> // Str),
            :favicon(%h<favicon> // Str),
            :author(%author),
            :language(%h<locale> // %h<language> // Str);
        if %h<expired>:exists {
            die "JSON Feed 'expired' must be a Bool, got {%h<expired>.^name}"
                unless %h<expired> ~~ Bool;
            %bless<expired> = %h<expired>;
        }
        self.bless(|%bless, :@items)
    }
}

method to-hash {
    $!hash-lock.protect: {
        # Feed-level metadata is cached; the result returned to callers is a
        # shallow copy with the author hash rebuilt. Items are regenerated per
        # call (see below), so callers cannot mutate cache state.
        $!cached-hash //= do {
            my %h;
            %h<version>       = $.version;
            %h<title>         = $.title         if $.title.defined;
            %h<home_page_url> = $.link          if $.link.defined;
            %h<feed_url>      = $.feed_url      if $.feed_url.defined;
            %h<description>   = $.description   if $.description.defined;
            %h<user_comment>  = $.user_comment  if $.user_comment.defined;
            %h<next_url>      = $.next_url      if $.next_url.defined;
            %h<icon>          = $.icon          if $.icon.defined;
            %h<favicon>       = $.favicon       if $.favicon.defined;
            %h<locale>        = $.language      if $.language.defined;
            %h<generator>     = $.generator     if $.generator.defined;
            %h<expired>       = $.expired       if $.expired.defined;

            if %.author<name>.defined || %.author<url>.defined || %.author<avatar>.defined {
                my %a;
                %a<name>   = %.author<name>   if %.author<name>.defined;
                %a<url>    = %.author<url>    if %.author<url>.defined;
                %a<avatar> = %.author<avatar> if %.author<avatar>.defined;
                %h<author> = %a;
            }

            %h
        }
        my %h = %($!cached-hash);
        if %h<author>:exists {
            my %a;
            %a{$_} = %h<author>{$_} for %h<author>.keys;
            %h<author> = %a;
        }
        # Items are rebuilt fresh on every call: JSONFeed::Item.to-hash
        # returns a new hash (with new nested containers) each time, which
        # is cheaper than deep-copying cached item hashes and guarantees
        # callers cannot mutate cache state.
        %h<items> = @.items.map(*.to-hash).Array;
        %h
    }
}

method to-json {
    $!json-lock.protect: { $!cached-json //= to-json $.to-hash }
}

method Str { $.to-json }

=begin pod

=head1 NAME

Syndicate::JSONFeed - JSON Feed 1.1

=head1 SYNOPSIS

=begin code :lang<raku>
my $feed = Syndicate::JSONFeed.new($json-string);
my $feed = Syndicate::JSONFeed.new(:title("My Feed"), :feed_url("..."), ...);
say $feed.to-json;
my %h = $feed.to-hash;
=end code

=head1 DESCRIPTION

Parses and generates JSON Feed 1.1. Does L<C<Syndicate::Feed>|rakudoc:Syndicate::Feed>.

B<Note:> When constructed from a hash, a missing C<version> is defaulted to
C<https://jsonfeed.org/version/1.1>. Auto-detection in L<C<Syndicate::Parse>|rakudoc:Syndicate::Parse>
is deliberately stricter — it only treats input as a JSON Feed when a C<version>
starting with C<https://jsonfeed.org/version/> is present, so that arbitrary JSON
documents are not mistaken for feeds.

=head1 ATTRIBUTES

=item C<$.title>, C<$.link>, C<$.description> - from Feed role
=item C<$.generator>, C<$.language> - from Feed role
=item C<$.version> - JSON Feed version (default: C<https://jsonfeed.org/version/1.1>)
=item C<$.feed_url> - Feed URL
=item C<$.user_comment> - User comment
=item C<$.next_url> - Next URL for pagination
=item C<$.icon> - Feed icon URL
=item C<$.favicon> - Favicon URL
=item C<%.author> - Author hash (name, url, avatar)
=item C<$.expired> - Whether feed is expired

=end pod
