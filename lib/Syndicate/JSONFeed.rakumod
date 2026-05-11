use v6.d;
use JSON::Fast;
use Syndicate::Feed;
use Syndicate::JSONFeed::Item;
use Syndicate::Utils;

unit class Syndicate::JSONFeed:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed;

has Str $.version = "https://jsonfeed.org/version/1.1";
has Str $.feed_url;
has Str $.user_comment;
has Str $.next_url;
has Str $.icon;
has Str $.favicon;
has %.author;
has Bool $.expired;

multi method new(Str $json) {
    my %h = from-json($json);
    self.new-from-hash(%h)
}

multi method new-from-hash(%h) {
    my $title       = %h<title> // Str;
    my $link        = %h<home_page_url> // %h<feed_url> // Str;
    my $desc        = %h<description> // Str;

    my %author;
    with %h<author> {
        %author<name>   = .<name> // Str;
        %author<url>    = .<url> // Str;
        %author<avatar> = .<avatar> // Str;
    }

    my @items;
    with %h<items> {
        for @$_ {
            @items.push: Syndicate::JSONFeed::Item.new-from-hash($_);
        }
    }

    my %bless = :$title, :$link, :description($desc),
        :feed_url(%h<feed_url> // Str),
        :user_comment(%h<user_comment> // Str),
        :next_url(%h<next_url> // Str),
        :icon(%h<icon> // Str),
        :favicon(%h<favicon> // Str),
        :author(%author),
        :language(%h<language> // Str);
    %bless<expired> = %h<expired> if %h<expired>:exists;
    self.bless(|%bless, :@items)
}

method to-hash {
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
    %h<language>      = $.language      if $.language.defined;
    %h<expired>       = $.expired       if $.expired.defined;

    if %.author<name>.defined || %.author<url>.defined || %.author<avatar>.defined {
        my %a;
        %a<name>   = %.author<name>   if %.author<name>.defined;
        %a<url>    = %.author<url>    if %.author<url>.defined;
        %a<avatar> = %.author<avatar> if %.author<avatar>.defined;
        %h<author> = %a;
    }

    if @.items {
        %h<items> = @.items.map(*.to-hash).Array;
    }

    %h
}

method to-json {
    to-json $.to-hash
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
