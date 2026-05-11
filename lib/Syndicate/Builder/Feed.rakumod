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
        :category($cat);
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
        :managingEditor($!author-name // Str);
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
        :$about;
    Syndicate::RSS::V1_0.new(|%bless, :@items)
}

method rss-str     { ~$.rss-feed     }

method rss1-str    { ~$.rss1-feed    }

method rss091-str  { ~$.rss091-feed  }

method atom-str    { ~$.atom-feed    }

method json-str    { $.json-feed.to-json }
