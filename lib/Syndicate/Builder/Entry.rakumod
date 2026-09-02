use v6.d;
use Syndicate::RSS::Item;
use Syndicate::RSS::V1_0::Item;
use Syndicate::Atom::Item;
use Syndicate::RSS::V0_91::Item;
use Syndicate::JSONFeed::Item;

unit class Syndicate::Builder::Entry:ver<0.0.4>:auth<zef:sasha>;

has Str $.title;
has Str $.link;
has Str $.summary;
has Str $.id;
has Str $.rights;
has DateTime $.updated;
has DateTime $.published;
has Str $!author-name;
has Str $!author-email;
has Str $!author-uri;
has @!categories;
has Str $!content;
has Str $!content-type;
has Str $!media-title;
has Str $!media-description;
has @!media-contents;
has @!media-thumbnails;
has Str $!comments;
has Str $!source;
has %.enclosure;

method title(Str $v?)      { $!title = $v if $v.defined; $!title }
method link(Str $v?)       { $!link = $v if $v.defined; $!link }
method summary(Str $v?)    { $!summary = $v if $v.defined; $!summary }
method id(Str $v?)         { $!id = $v if $v.defined; $!id }
method rights(Str $v?)     { $!rights = $v if $v.defined; $!rights }
method updated(DateTime $v?) { $!updated = $v if $v.defined; $!updated }
method published(DateTime $v?) { $!published = $v if $v.defined; $!published }

method content(Str $v?, Str :$type) {
    $!content      = $v    if $v.defined;
    $!content-type = $type if $type.defined;
    $!content
}

method media-title(Str $v?) { $!media-title = $v if $v.defined; $!media-title }

method media-description(Str $v?) { $!media-description = $v if $v.defined; $!media-description }

method media-content(Str :$url, Str :$type, Str :$medium, :$width, :$height, :$duration, Str :$title, Str :$description) {
    die "media-content requires url" unless $url.defined;
    my %mc = :$url, :$type;
    %mc<medium>     = $medium     if $medium.defined;
    %mc<width>      = $width      if $width.defined;
    %mc<height>     = $height     if $height.defined;
    %mc<duration>   = $duration   if $duration.defined;
    %mc<title>       = $title       if $title.defined;
    %mc<description> = $description if $description.defined;
    @!media-contents.push: %mc;
    @!media-contents
}

method media-thumbnail(Str :$url, :$width, :$height, :$time) {
    die "media-thumbnail requires url" unless $url.defined;
    my %mt = :$url;
    %mt<width>  = $width  if $width.defined;
    %mt<height> = $height if $height.defined;
    %mt<time>   = $time   if $time.defined;
    @!media-thumbnails.push: %mt;
    @!media-thumbnails
}

method author(Str :$name, Str :$email, Str :$uri) {
    $!author-name  = $name  if $name.defined;
    $!author-email = $email if $email.defined;
    $!author-uri   = $uri   if $uri.defined;
    %(:name($!author-name), :email($!author-email), :uri($!author-uri))
}

method add-category(Str $v) {
    @!categories.push: $v;
    self
}

method categories() { @!categories.List }

method comments(Str $v?) { $!comments = $v if $v.defined; $!comments }

method source(Str $v?)   { $!source = $v if $v.defined; $!source }

method enclosure(Str :$url, Str :$length, Str :$type) {
    %!enclosure<url>    = $url    if $url.defined;
    %!enclosure<length> = $length if $length.defined;
    %!enclosure<type>   = $type   if $type.defined;
    %!enclosure
}

method !require-text(Str $format, Str $field, $value --> Str) {
    $value.defined && $value.chars
        ?? $value
        !! die "$format item requires $field"
}

method build-rss-item {
    my $title = self!require-text("RSS 2.0", "title", $!title);
    my $link  = self!require-text("RSS 2.0", "link", $!link);
    my $item-id = $!id // $link // Str;
    my %bless = :$title, :$link, :summary($!summary // Str),
        :author($!author-name // Str),
        :id($item-id),
        # content maps to content:encoded in RSS, <content> in Atom,
        # and content_html/content_text in JSON Feed
        :content($!content // Str),
        :guid($item-id),
        :media-title($!media-title // Str),
        :media-description($!media-description // Str);
    %bless<updated>  = $!updated if $!updated.defined;
    %bless<comments>  = $!comments if $!comments.defined;
    %bless<source>    = $!source if $!source.defined;
    %bless<enclosure> = %!enclosure if %!enclosure;
    Syndicate::RSS::Item.bless(|%bless,
        :categories(@!categories),
        :media-contents(@!media-contents),
        :media-thumbnails(@!media-thumbnails))
}

method build-v0_91-item {
    my $title = self!require-text("RSS 0.91", "title", $!title);
    my $link  = self!require-text("RSS 0.91", "link", $!link);
    my $desc  = self!require-text("RSS 0.91", "description", $!summary);
    my $item-id = $!id // $link // Str;
    my %bless = :$title, :$link, :summary($desc),
        :id($item-id);
    # has-dc-creator is intentionally not set — V0_91 does not use dc:
    # namespace. The xmlns:dc declaration should only appear in formats
    # that support Dublin Core (RSS 2.0, RSS 1.0).
    # Content, author, comments, source, and enclosure are intentionally
    # not passed — the RSS 0.91 DTD only allows title, link, and
    # description inside <item>.
    # is-v091 is set by V0_91::Item's TWEAK; the shared role's default
    # would otherwise produce RSS 2.0-flavored output.
    Syndicate::RSS::V0_91::Item.bless(|%bless)
}

method build-json-item {
    my $title = self!require-text("JSON Feed", "title", $!title);
    my %author-detail;
    %author-detail<name> = $!author-name if $!author-name.defined;
    %author-detail<url>  = $!author-uri  if $!author-uri.defined;
    # JSON Feed author object has no 'email' field, so skip it

    my $item-id = $!id // $!link // Str;
    my $c = $!content // Str;
    my %bless = :$title,
        :id($item-id),
        :summary($!summary // Str);
    if $c.defined {
        if $!content-type.defined && ($!content-type.contains('html') || $!content-type.contains('xhtml')) {
            %bless<content_html> = $c;
        } else {
            %bless<content_text> = $c;
        }
    }
    %bless<date_published> = $!published.Str if $!published.defined;
    %bless<date_modified>  = $!updated.Str   if $!updated.defined;
    my @authors;
    @authors.push: %author-detail if %author-detail;
    %bless<url>     = $!link.defined ?? $!link !! Str;
    %bless<authors> = @authors if @authors;
    %bless<tags>    = @!categories.List if @!categories;
    Syndicate::JSONFeed::Item.new-from-hash(%bless)
}

method build-v1_0-item {
    my $title = self!require-text("RSS 1.0", "title", $!title);
    my $link  = self!require-text("RSS 1.0", "link", $!link);
    my $item-id = $!id // $link // Str;
    my %bless = :$title, :$link,
        :summary($!summary // Str),
        :id($item-id),
        :about($item-id),
        :content($!content // Str),

        :author($!author-name // Str),
        :has-dc-creator($!author-name.defined);
    %bless<updated>  = $!updated if $!updated.defined;
    %bless<comments>  = $!comments if $!comments.defined;
    %bless<source>    = $!source if $!source.defined;
    %bless<enclosure> = %!enclosure if %!enclosure;
    my @dc-subjects = @!categories;
    # is-rdf is set by V1_0::Item's TWEAK; the shared role's default would
    # otherwise produce RSS 2.0-flavored output.
    Syndicate::RSS::V1_0::Item.bless(|%bless, :categories(@!categories), :@dc-subjects)
}

method build-atom-item(:$now = DateTime.now) {
    my %author-detail;
    %author-detail<name>  = $!author-name  if $!author-name.defined;
    %author-detail<email> = $!author-email if $!author-email.defined;
    %author-detail<uri>   = $!author-uri   if $!author-uri.defined;

    my $atom-id = $!id // $!link // Str;
    my %bless = :title(self!require-text("Atom", "title", $!title)), :link($!link // Str),
        :id($atom-id),
        :summary($!summary // Str),
        :author($!author-name // Str),
        :author-detail(%author-detail),
        :content($!content // Str),
        :content-type($!content-type // Str),
        :rights($!rights // Str);
    # Atom requires updated per spec; fall back to published, then to now
    %bless<updated> = $!updated if $!updated.defined;
    %bless<updated> //= $!published if $!published.defined;
    %bless<updated> //= $now;
    %bless<published> = $!published if $!published.defined;
    my @cats = @!categories;
    Syndicate::Atom::Item.new(|%bless, :categories(@cats))
}

=begin pod

=head1 NAME

Syndicate::Builder::Entry - Entry builder used by L<C<Syndicate::Builder::Feed>|rakudoc:Syndicate::Builder::Feed>

=head1 SYNOPSIS

=begin code :lang<raku>
my $fb = Syndicate::Builder::Feed.new;
my $e = $fb.add-entry;
$e.title("Article");
$e.link("https://example.com/1");
$e.summary("Description");
$e.id("urn:uuid:abc-123");
$e.author(:name("Jane"), :email("jane@example.com"));
$e.updated(DateTime.now);
$e.published(DateTime.now);
$e.add-category("Tech");
$e.content("<p>Hello</p>", :type("xhtml"));
=end code

=head1 DESCRIPTION

Created via C<add-entry> on L<C<Syndicate::Builder::Feed>|rakudoc:Syndicate::Builder::Feed>.
Accumulates entry-level data used by all output format generators.

=head1 METHODS

=item C<title(Str $v?)> - get/set title
=item C<link(Str $v?)> - get/set link
=item C<summary(Str $v?)> - get/set summary/description
=item C<id(Str $v?)> - get/set entry ID (maps to guid/atom:id/id)
=item C<rights(Str $v?)> - get/set rights
=item C<updated(DateTime $v?)> - get/set updated/modified date
=item C<published(DateTime $v?)> - get/set published date
=item C<content(Str $v?, :$type)> - get/set content body with optional MIME type
=item C<media-content(Str :$url, Str :$type, Str :$medium, :$width, :$height, :$duration, Str :$title, Str :$description)> - add a media:content element; C<:medium> and content-level C<:title>/C<:description> are optional
=item C<media-thumbnail(Str :$url, :$width, :$height, :$time)> - add a media:thumbnail element
=item C<author(:$name, :$email, :$uri)> - get/set author details
=item C<add-category(Str $v)> - add a category (returns C<self> for chaining)
=item C<categories()> - get the list of categories
=end pod
