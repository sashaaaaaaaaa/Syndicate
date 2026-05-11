use v6.d;
use Syndicate::RSS;
use Syndicate::RSS::V0_91;
use Syndicate::RSS::V1_0;
use Syndicate::Atom;
use Syndicate::JSONFeed;
use Syndicate::Builder::Entry;

unit class Syndicate::Builder::Feed:ver<0.0.1>:auth<zef:sasha>;

has Str $.title;
has Str $.link;
has Str $.description;
has Str $.id;
has Str $.language;
has Str $.rights;
has Str $.generator = "Syndicate";
has DateTime $.updated;
has Str $.icon;
has Str $.logo;
has Str $!author-name;
has Str $!author-email;
has Str $!author-uri;
has @!categories;
has @!entries;
has Str $!itunes-author;
has Str $!itunes-summary;
has Str $!atom-self-link;

method title(Str $v?)       { $!title = $v if $v.defined; $!title }
method link(Str $v?)        { $!link = $v if $v.defined; $!link }
method description(Str $v?) { $!description = $v if $v.defined; $!description }
method id(Str $v?)          { $!id = $v if $v.defined; $!id }
method language(Str $v?)    { $!language = $v if $v.defined; $!language }
method rights(Str $v?)      { $!rights = $v if $v.defined; $!rights }
method generator(Str $v?)   { $!generator = $v if $v.defined; $!generator }
method updated(DateTime $v?) { $!updated = $v if $v.defined; $!updated }
method icon(Str $v?)        { $!icon = $v if $v.defined; $!icon }
method logo(Str $v?)        { $!logo = $v if $v.defined; $!logo }

method author(Str :$name, Str :$email, Str :$uri) {
    $!author-name  = $name  if $name.defined;
    $!author-email = $email if $email.defined;
    $!author-uri   = $uri   if $uri.defined;
    %(:name($!author-name), :email($!author-email), :uri($!author-uri))
}

method itunes-author(Str $v?)   { $!itunes-author = $v if $v.defined; $!itunes-author }
method itunes-summary(Str $v?)  { $!itunes-summary = $v if $v.defined; $!itunes-summary }
method atom-self-link(Str $v?)  { $!atom-self-link = $v if $v.defined; $!atom-self-link }

method category(Str $v?) {
    @!categories.push: $v if $v.defined;
    @!categories
}

method add-entry {
    my $entry = Syndicate::Builder::Entry.new;
    @!entries.push: $entry;
    $entry
}

method entries { @!entries }

method rss-feed {
    my @items = @!entries.map(*.build-rss-item);
    my $cat = @!categories ?? @!categories[0] !! Str;
    my %bless = :title($!title // Str), :link($!link // Str),
        :description($!description // Str),
        :language($!language // Str),
        :copyright($!rights // Str),
        :managingEditor($!author-name // Str),
        :generator($!generator // Str),
        :category($cat),
        :itunes-author($!itunes-author // Str),
        :itunes-summary($!itunes-summary // Str);
    %bless<atom-self-link> = $!atom-self-link if $!atom-self-link.defined;
    %bless<pubDate> = $!updated if $!updated ~~ DateTime;
    Syndicate::RSS.new(|%bless, :@items)
}

method atom-feed {
    my @items = @!entries.map(*.build-atom-item);
    my %author-detail;
    %author-detail<name>  = $!author-name  if $!author-name.defined;
    %author-detail<email> = $!author-email if $!author-email.defined;
    %author-detail<uri>   = $!author-uri   if $!author-uri.defined;
    my $atom-id = $!id // $!link // "";
    my $subtitle = $!description // Str;
    my %bless = :title($!title // Str), :id($atom-id),
        :link($!link // Str),
        :description($subtitle),
        :$subtitle,
        :rights($!rights // Str),
        :generator($!generator // Str),
        :icon($!icon // Str),
        :logo($!logo // Str),
        :author-detail(%author-detail);
    %bless<updated> = $!updated // DateTime.now;
    my @cats = @!categories;
    Syndicate::Atom.new(|%bless, :@items, :categories(@cats))
}

method rss091-feed {
    my @items = @!entries.map(*.build-v0_91-item);
    my %bless = :title($!title // Str), :link($!link // Str),
        :description($!description // Str),
        :language($!language // Str),
        :copyright($!rights // Str),
        :managingEditor($!author-name // Str),
        :generator($!generator // Str);
    %bless<pubDate> = $!updated if $!updated ~~ DateTime;
    Syndicate::RSS::V0_91.new(|%bless, :@items)
}

method json-feed {
    my @items = @!entries.map(*.build-json-item);
    my %author;
    %author<name> = $!author-name if $!author-name.defined;
    %author<url>  = $!author-email if $!author-email.defined;
    my $feed-id = $!id // $!link // Str;
    my %bless = :title($!title // Str), :link($!link // Str),
        :description($!description // Str),
        :feed_url($feed-id),
        :language($!language // Str),
        :generator($!generator // Str),
        :icon($!icon // Str),
        :favicon($!logo // Str),
        :author(%author);
    Syndicate::JSONFeed.new(|%bless, :@items)
}

method rss1-feed {
    my @items = @!entries.map(*.build-v1_0-item);
    my $about = $!id // $!link // Str;
    my %bless = :title($!title // Str), :link($!link // Str),
        :description($!description // Str),
        :$about,
        :generator($!generator // Str),
        :language($!language // Str);
    Syndicate::RSS::V1_0.new(|%bless, :@items)
}

method rss-str     { ~$.rss-feed     }

method rss1-str    { ~$.rss1-feed    }

method rss091-str  { ~$.rss091-feed  }

method atom-str    { ~$.atom-feed    }

method json-str    { $.json-feed.to-json }

=begin pod

=head1 NAME

Syndicate::Builder::Feed - Format-agnostic feed builder

=head1 SYNOPSIS

=begin code :lang<raku>
use Syndicate::Builder::Feed;

my $fb = Syndicate::Builder::Feed.new;
$fb.title("My Feed");
$fb.link("https://example.com");
$fb.description("A test feed");
$fb.language("en");

my $e = $fb.add-entry;
$e.title("Article 1");
$e.link("https://example.com/1");

say $fb.rss-str;    # RSS 2.0 XML
say $fb.atom-str;   # Atom 1.0 XML
say $fb.json-str;   # JSON Feed
=end code

=head1 DESCRIPTION

Accumulates feed and entry data through a uniform API, then generates
output in any supported format. Eliminates the need to learn each
format's constructor signatures.

=head1 METHODS

=head2 Feed-level

=item C<title(Str $v?)> - get/set title
=item C<link(Str $v?)> - get/set link
=item C<description(Str $v?)> - get/set description
=item C<id(Str $v?)> - get/set feed ID
=item C<language(Str $v?)> - get/set language
=item C<rights(Str $v?)> - get/set copyright/rights
=item C<generator(Str $v?)> - get/set generator (default: "Syndicate")
=item C<updated(DateTime $v?)> - get/set last updated time
=item C<icon(Str $v?)> - get/set feed icon URL
=item C<logo(Str $v?)> - get/set feed logo URL
=item C<author(:$name, :$email, :$uri)> - get/set author details
=item C<category(Str $v?)> - add/get categories
=item C<itunes-author(Str $v?)> - get/set iTunes author
=item C<itunes-summary(Str $v?)> - get/set iTunes summary

=head2 Entry management

=item C<add-entry> - create and return a new L<C<Syndicate::Builder::Entry>|rakudoc:Syndicate::Builder::Entry>
=item C<entries> - return all entries

=head2 Output generation

=item C<rss-feed> - returns L<C<Syndicate::RSS>|rakudoc:Syndicate::RSS>
=item C<atom-feed> - returns L<C<Syndicate::Atom>|rakudoc:Syndicate::Atom>
=item C<rss091-feed> - returns L<C<Syndicate::RSS::V0_91>|rakudoc:Syndicate::RSS::V0_91>
=item C<rss1-feed> - returns L<C<Syndicate::RSS::V1_0>|rakudoc:Syndicate::RSS::V1_0>
=item C<json-feed> - returns L<C<Syndicate::JSONFeed>|rakudoc:Syndicate::JSONFeed>
=item C<rss-str> - RSS 2.0 XML string
=item C<atom-str> - Atom 1.0 XML string
=item C<rss091-str> - RSS 0.91 XML string
=item C<rss1-str> - RSS 1.0 XML string
=item C<json-str> - JSON Feed string

=end pod
