use v6.d;
use Syndicate::Feed;
use Syndicate::RSS;
use Syndicate::RSS::Item::Common;
use Syndicate::RSS::V0_91;
use Syndicate::RSS::V1_0;
use Syndicate::Atom;
use Syndicate::JSONFeed;
use Syndicate::Builder::Entry;

unit class Syndicate::Builder::Feed:ver<0.0.2>:auth<zef:sasha>;

has Str $.title;
has Str $.link;
has Str $.description;
has Str $.id;
has Str $.language;
has Str $.rights;
has Str $.generator = "Syndicate";
has DateTime $.updated;
has Str $.icon;
has Str $.feed-url;
has Str $.version;
has Str $.logo;
has Str $!author-name;
has Str $!author-email;
has Str $!author-uri;
has @!categories;
has @!entries;
has Str $!itunes-author;
has Str $!itunes-summary;
has Str $!atom-self-link;
has %.image;

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
method feed-url(Str $v?)    { $!feed-url = $v if $v.defined; $!feed-url }
method version(Str $v?)     { $!version = $v if $v.defined; $!version }

method author(Str :$name, Str :$email, Str :$uri) {
    $!author-name  = $name  if $name.defined;
    $!author-email = $email if $email.defined;
    $!author-uri   = $uri   if $uri.defined;
    %(:name($!author-name), :email($!author-email), :uri($!author-uri))
}

method itunes-author(Str $v?)   { $!itunes-author = $v if $v.defined; $!itunes-author }
method itunes-summary(Str $v?)  { $!itunes-summary = $v if $v.defined; $!itunes-summary }
method atom-self-link(Str $v?)  { $!atom-self-link = $v if $v.defined; $!atom-self-link }

method image(Str :$url, Str :$title, Str :$link, Int :$width, Int :$height) {
    %!image<url>    = $url    if $url.defined;
    %!image<title>   = $title  if $title.defined;
    %!image<link>    = $link   if $link.defined;
    %!image<width>   = $width  if $width.defined;
    %!image<height>  = $height if $height.defined;
    %!image
}

method category(Str $v?) {
    @!categories.push: $v if $v.defined;
    @!categories.List
}

method add-entry {
    my $entry = Syndicate::Builder::Entry.new;
    @!entries.push: $entry;
    $entry
}

method entries { @!entries }

method new-from-feed(Syndicate::Feed $feed --> Syndicate::Builder::Feed) {
    my $b = self.defined ?? self !! self.new;
    $b.title($feed.title)             if $feed.title.defined;
    $b.link($feed.link)               if $feed.link.defined;
    $b.description($feed.description) if $feed.description.defined;
    $b.generator($feed.generator)     if $feed.generator.defined;
    $b.language($feed.language)       if $feed.language.defined;

    given $feed {
        when Syndicate::Atom {
            $b.id($_.id)              if $_.id.defined;
            $b.rights($_.rights)      if $_.rights.defined;
            $b.icon($_.icon)          if $_.icon.defined;
            $b.logo($_.logo)          if $_.logo.defined;
            $b.updated($_.updated)    if $_.updated.defined;
            $b.category($_) for @($_.categories);
            my %ad = $_.author-detail;
            $b.author(:name(%ad<name>), :email(%ad<email>), :uri(%ad<uri>))
                if %ad<name>.defined || %ad<email>.defined || %ad<uri>.defined;
            my @self-links = @($_.link-self);
            $b.atom-self-link(@self-links[0]<href>) if @self-links[0].defined;
        }
        when Syndicate::RSS {
            $b.rights($_.copyright)       if $_.copyright.defined;
            $b.author(:email($_.managingEditor)) if $_.managingEditor.defined;
            $b.updated($_.lastBuildDate)  if $_.lastBuildDate.defined;
            $b.itunes-author($_.itunes-author)   if $_.itunes-author.defined;
            $b.itunes-summary($_.itunes-summary) if $_.itunes-summary.defined;
            $b.atom-self-link($_.atom-self-link) if $_.atom-self-link.defined;
            $b.category($_) for @($_.categories);
            $b!copy-image($_.image);
        }
        when Syndicate::RSS::V0_91 {
            $b.rights($_.copyright)       if $_.copyright.defined;
            $b.author(:email($_.managingEditor)) if $_.managingEditor.defined;
            $b.updated($_.lastBuildDate)  if $_.lastBuildDate.defined;
            $b.itunes-author($_.itunes-author)   if $_.itunes-author.defined;
            $b.itunes-summary($_.itunes-summary) if $_.itunes-summary.defined;
            $b!copy-image($_.image);
        }
        when Syndicate::RSS::V1_0 {
            $b.id($_.about)               if $_.about.defined;
            $b.itunes-author($_.itunes-author)   if $_.itunes-author.defined;
            $b.itunes-summary($_.itunes-summary) if $_.itunes-summary.defined;
            $b.category($_) for @($_.categories);
            $b!copy-image($_.image);
        }
        when Syndicate::JSONFeed {
            $b.feed-url($_.feed_url)  if $_.feed_url.defined;
            $b.version($_.version)    if $_.version.defined;
            $b.icon($_.icon)          if $_.icon.defined;
            my %a = $_.author;
            $b.author(:name(%a<name>), :uri(%a<url>))
                if %a<name>.defined || %a<url>.defined;
        }
    }

    for $feed.items -> $item {
        my $e = $b.add-entry;
        $e.title($item.title)         if $item.title.defined;
        $e.link($item.link)           if $item.link.defined;
        $e.summary($item.summary)     if $item.summary.defined;
        $e.id($item.id)               if $item.id.defined;
        $e.updated($item.updated)     if $item.updated.defined;
        $e.content($item.content)     if $item.content.defined;

        given $item {
            when Syndicate::Atom::Item {
                my %ad = $_.author-detail;
                $e.author(:name(%ad<name>), :email(%ad<email>), :uri(%ad<uri>))
                    if %ad<name>.defined || %ad<email>.defined || %ad<uri>.defined;
                $e.published($_.published)  if $_.published.defined;
                $e.rights($_.rights)        if $_.rights.defined;
                if $_.content.defined {
                    $_.content-type.defined
                        ?? $e.content($_.content, :type($_.content-type))
                        !! $e.content($_.content);
                }
                $e.category($_) for @($_.categories);
                if $_.source-feed<link>.defined {
                    $e.source($_.source-feed<link>);
                }
            }
            when Syndicate::RSS::Item::Common {
                $e.author(:name($_.author)) if $_.author.defined;
                $e.category($_) for @($_.categories);
                $e.comments($_.comments)    if $_.comments.defined;
                $e.source($_.source)        if $_.source.defined;
                # content:encoded is HTML by definition; typing it lets
                # JSON output emit content_html instead of content_text.
                $e.content($_.content, :type<html>) if $_.content.defined;
                if $_.enclosure<url>.defined {
                    my %en;
                    %en<url>    = $_.enclosure<url>;
                    %en<length> = $_.enclosure<length> if $_.enclosure<length>.defined;
                    %en<type>   = $_.enclosure<type>   if $_.enclosure<type>.defined;
                    $e.enclosure(|%en);
                }
                $e.media-title($_.media-title)         if $_.media-title.defined;
                $e.media-description($_.media-description) if $_.media-description.defined;
                for @($_.media-contents) -> %mc {
                    next unless %mc<url>.defined;
                    my %m;
                    %m<url>      = %mc<url>;
                    %m<type>     = %mc<type>     if %mc<type>.defined;
                    %m<width>    = %mc<width>    if %mc<width>.defined;
                    %m<height>   = %mc<height>   if %mc<height>.defined;
                    %m<duration> = %mc<duration> if %mc<duration>.defined;
                    $e.media-content(|%m);
                }
                for @($_.media-thumbnails) -> %mt {
                    next unless %mt<url>.defined;
                    my %t;
                    %t<url>    = %mt<url>;
                    %t<width>  = %mt<width>  if %mt<width>.defined;
                    %t<height> = %mt<height> if %mt<height>.defined;
                    %t<time>   = %mt<time>   if %mt<time>.defined;
                    $e.media-thumbnail(|%t);
                }
            }
            when Syndicate::JSONFeed::Item {
                my @authors = @($_.authors);
                if @authors {
                    my %a = @authors[0];
                    $e.author(:name(%a<name>), :uri(%a<url>))
                        if %a<name>.defined || %a<url>.defined;
                }
                $e.published($_.date_published) if $_.date_published.defined;
                $e.updated($_.date_modified)    if $_.date_modified.defined;
                if $_.content_html.defined && $_.content_html.chars {
                    $e.content($_.content_html, :type<html>);
                } elsif $_.content_text.defined && $_.content_text.chars {
                    $e.content($_.content_text);
                }
                $e.category($_) for @($_.tags);
            }
        }
    }
    $b
}

method !copy-image(%image) {
    return unless %image<url>.defined || %image<title>.defined;
    my %img;
    %img<url>    = %image<url>    if %image<url>.defined;
    %img<title>  = %image<title>  if %image<title>.defined;
    %img<link>   = %image<link>   if %image<link>.defined;
    %img<width>  = %image<width>  if %image<width>.defined;
    %img<height> = %image<height> if %image<height>.defined;
    self.image(|%img)
}

method rss-feed {
    die "RSS 2.0 feed requires title"   unless $!title.defined;
    die "RSS 2.0 feed requires link"    unless $!link.defined;
    die "RSS 2.0 feed requires description" unless $!description.defined;
    my @items = @!entries.map(*.build-rss-item);
    my @cats = @!categories;
    my %bless;
    %bless<title>             = $!title          if $!title.defined;
    %bless<link>              = $!link           if $!link.defined;
    %bless<description>       = $!description    if $!description.defined;
    %bless<language>          = $!language       if $!language.defined;
    %bless<copyright>         = $!rights         if $!rights.defined;
    %bless<managingEditor>    = $!author-email    if $!author-email.defined;
    %bless<generator>         = $!generator      if $!generator.defined;
    %bless<itunes-author>     = $!itunes-author  if $!itunes-author.defined;
    %bless<itunes-summary>    = $!itunes-summary if $!itunes-summary.defined;
    %bless<atom-self-link>    = $!atom-self-link if $!atom-self-link.defined;
    %bless<lastBuildDate>     = $.updated        if $.updated.defined;
    %bless<image> = %!image;
    Syndicate::RSS.new(|%bless, :categories(@cats), :@items)
}

method atom-feed {
    die "Atom feed requires title"   unless $!title.defined;
    die "Atom feed requires link"    unless $!link.defined;
    # One timestamp for the whole build so entries without updated/published
    # don't each get a slightly different DateTime.now.
    my $now = DateTime.now;
    my @items = @!entries.map({ $_.build-atom-item(:$now) });
    my %author-detail;
    %author-detail<name>  = $!author-name  if $!author-name.defined;
    %author-detail<email> = $!author-email if $!author-email.defined;
    %author-detail<uri>   = $!author-uri   if $!author-uri.defined;
    my $atom-id = $!id // $!link // die "Syndicate::Builder::Feed: Atom feed requires id or link";
    my $subtitle = $!description // Str;
    my %bless;
    %bless<title>         = $!title       if $!title.defined;
    %bless<id>            = $atom-id;
    %bless<link>          = $!link        if $!link.defined;
    %bless<description>   = $subtitle;
    %bless<subtitle>      = $subtitle     if $subtitle.defined;
    %bless<rights>        = $!rights      if $!rights.defined;
    %bless<generator>     = $!generator   if $!generator.defined;
    %bless<icon>          = $!icon        if $!icon.defined;
    %bless<logo>          = $!logo        if $!logo.defined;
    %bless<author-detail> = %author-detail;
    %bless<updated>       = $.updated  if $.updated.defined;
    my @cats = @!categories;
    Syndicate::Atom.new(|%bless, :@items, :categories(@cats))
}

method rss091-feed {
    die "RSS 0.91 feed requires title" unless $!title.defined;
    die "RSS 0.91 feed requires link"  unless $!link.defined;
    # The RSS 0.91 DTD requires description in <channel>, mirroring the
    # RSS 2.0 builder path. Language stays optional.
    die "RSS 0.91 feed requires description" unless $!description.defined;
    my @items = @!entries.map(*.build-v0_91-item);
    my %bless;
    %bless<title>           = $!title        if $!title.defined;
    %bless<link>            = $!link         if $!link.defined;
    %bless<description>     = $!description  if $!description.defined;
    %bless<language>        = $!language     if $!language.defined;
    %bless<copyright>       = $!rights       if $!rights.defined;
    %bless<managingEditor>  = $!author-email if $!author-email.defined;
    %bless<generator>       = $!generator    if $!generator.defined;
    %bless<lastBuildDate>   = $!updated      if $!updated.defined;
    %bless<itunes-author>  = $!itunes-author  if $!itunes-author.defined;
    %bless<itunes-summary> = $!itunes-summary if $!itunes-summary.defined;
    %bless<image> = %!image;
    warn "Warning: RSS 0.91 does not support feed-level categories; {@!categories.elems} categories dropped"
        if @!categories;
    Syndicate::RSS::V0_91.new(|%bless, :@items)
}

method json-feed {
    die "JSON Feed requires title" unless $!title.defined;
    my @items = @!entries.map(*.build-json-item);
    my %author;
    %author<name> = $!author-name if $!author-name.defined;
    %author<url>  = $!author-uri  if $!author-uri.defined;
    # JSON Feed author object has no 'email' field, so skip it
    my %bless;
    %bless<title>       = $!title       if $!title.defined;
    %bless<link>        = $!link        if $!link.defined;
    %bless<description> = $!description if $!description.defined;
    %bless<feed_url>    = $!feed-url    if $!feed-url.defined;
    %bless<version>     = $!version     if $!version.defined;
    %bless<language>    = $!language    if $!language.defined;
    %bless<generator>   = $!generator   if $!generator.defined;
    %bless<icon>        = $!icon        if $!icon.defined;
    %bless<author>      = %author if %author;
    Syndicate::JSONFeed.new(|%bless, :@items)
}

method rss1-feed {
    die "RSS 1.0 feed requires title" unless $!title.defined;
    die "RSS 1.0 feed requires link"  unless $!link.defined;
    die "RSS 1.0 feed requires description" unless $!description.defined;
    my @items = @!entries.map(*.build-v1_0-item);
    my @cats = @!categories;
    my $about = $!id // $!link // Str;
    my %bless;
    %bless<title>       = $!title       if $!title.defined;
    %bless<link>        = $!link        if $!link.defined;
    %bless<description> = $!description if $!description.defined;
    %bless<about>       = $about        if $about.defined && $about.chars;
    %bless<generator>      = $!generator      if $!generator.defined;
    %bless<language>       = $!language       if $!language.defined;
    %bless<itunes-author>  = $!itunes-author  if $!itunes-author.defined;
    %bless<itunes-summary> = $!itunes-summary if $!itunes-summary.defined;
    %bless<image> = %!image;
    Syndicate::RSS::V1_0.new(|%bless, :categories(@cats), :@items)
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

B<Note:> The C<updated> timestamp is mapped to C<lastBuildDate> in RSS (2.0,
0.91) and to C<updated> in Atom. These have different semantics
(publication vs last modification) — the builder intentionally uses a
single source of truth for simplicity. Use L<C<Syndicate::Builder::Entry>|rakudoc:Syndicate::Builder::Entry>'s
C<published> method when you need distinct publication and modification
timestamps in Atom output.

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
=item C<author(:$name, :$email, :$uri)> - get/set author details. In RSS output, C<:$email> maps to C<managingEditor>.
=item C<category(Str $v?)> - add/get categories
=item C<itunes-author(Str $v?)> - get/set iTunes author
=item C<itunes-summary(Str $v?)> - get/set iTunes summary

=head2 Entry management

=item C<add-entry> - create and return a new L<C<Syndicate::Builder::Entry>|rakudoc:Syndicate::Builder::Entry>
=item C<entries> - return all entries

=head2 Feed construction

=item C<new-from-feed(Syndicate::Feed $feed)> - populate this builder from an
existing parsed feed (any C<Syndicate::Feed>-compatible object), copying every
field the builder models. Lets you convert between formats: parse the source,
call C<new-from-feed>, then emit the target format. Only builder-supported
fields are copied; format-specific extras (RSS C<webMaster>/C<docs>/C<ttl>/
C<pubDate>, Atom contributors and extra/self links, media groups, item-level
iTunes fields, JSON C<external_url>/C<image>/C<banner_image>, and so on) are
not carried over. Emission may still die if the target format requires a field
the source does not have (e.g. an Atom feed without a description cannot be
emitted as RSS 2.0).

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
