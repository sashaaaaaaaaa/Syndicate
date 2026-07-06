use v6.d;
use Syndicate::RSS::Item;
use Syndicate::RSS::V1_0::Item;
use Syndicate::Atom::Item;
use Syndicate::RSS::V0_91::Item;
use Syndicate::JSONFeed::Item;

unit class Syndicate::Builder::Entry:ver<0.0.1>:auth<zef:sasha>;

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

method media-content(Str :$url, Str :$type, :$width, :$height, :$duration) {
    my %mc = :$url, :$type;
    %mc<width>    = $width    if $width.defined;
    %mc<height>   = $height   if $height.defined;
    %mc<duration> = $duration if $duration.defined;
    @!media-contents.push: %mc;
    @!media-contents
}

method media-thumbnail(Str :$url, :$width, :$height, :$time) {
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

method category(Str $v?) {
    @!categories.push: $v if $v.defined;
    @!categories
}

method build-rss-item {
    my $item-id = $!id // $!link // Str;
    my %bless = :title($!title // Str), :link($!link // Str),
        :summary($!summary // Str),
        :author($!author-name // Str),
        :id($item-id),
        # content maps to content:encoded in RSS, <content> in Atom,
        # and content_html/content_text in JSON Feed
        :content($!content // Str),
        :guid($item-id),
        :media-title($!media-title // Str),
        :media-description($!media-description // Str);
    %bless<updated> = $!updated if $!updated.defined;
    Syndicate::RSS::Item.new(|%bless,
        :categories(@!categories),
        :media-contents(@!media-contents),
        :media-thumbnails(@!media-thumbnails))
}

method build-v0_91-item {
    my $item-id = $!id // $!link // Str;
    my %bless = :title($!title // Str), :link($!link // Str),
        :summary($!summary // Str),
        :id($item-id),
        :content($!content // Str);
    %bless<author> = $!author-name if $!author-name.defined;
    # has-dc-creator is intentionally not set — V0_91 does not use dc:
    # namespace. The xmlns:dc declaration should only appear in formats
    # that support Dublin Core (RSS 2.0, RSS 1.0).
    # id and content are passed for role-interface consistency
    # but V0_91::Item ignores them (format has no guid/content element)
    Syndicate::RSS::V0_91::Item.new(|%bless)
}

method build-json-item {
    my %author-detail;
    %author-detail<name> = $!author-name if $!author-name.defined;
    # JSON Feed author object has no 'email' field, so skip it

    my $item-id = $!id // $!link // Str;
    my $c = $!content // Str;
    my %bless = :title($!title // Str), :link($!link // Str),
        :id($item-id),
        :summary($!summary // Str),
        :content($c);
    if $c.defined {
        if $!content-type.defined && ($!content-type.contains('html') || $!content-type.contains('xhtml')) {
            %bless<content_html> = $c;
        } else {
            %bless<content_text> = $c;
        }
    }
    %bless<date_published> = $!published.Str if $!published.defined;
    %bless<date_modified>  = $!updated.Str   if $!updated.defined;
    my @tags = @!categories;
    my @authors;
    @authors.push: %author-detail if %author-detail;
    my %item-hash = %bless;
    %item-hash<url>     = %item-hash<link>.defined ?? %item-hash<link> !! Str;
    %item-hash<authors> = @authors if @authors;
    %item-hash<tags>    = @tags    if @tags;
    Syndicate::JSONFeed::Item.new-from-hash(%item-hash)
}

method build-v1_0-item {
    my $about = $!id // $!link // Str;
    my $item-id = $!id // $!link // Str;
    my %bless = :title($!title // Str), :link($!link // Str),
        :summary($!summary // Str),
        :id($item-id),
        :content($!content // Str),
        :$about,
        :author($!author-name // Str),
        :has-dc-creator($!author-name.defined);
    %bless<updated> = $!updated if $!updated.defined;
    my @dc-subjects = @!categories;
    Syndicate::RSS::V1_0::Item.new(|%bless, :@dc-subjects)
}

method build-atom-item {
    my %author-detail;
    %author-detail<name>  = $!author-name  if $!author-name.defined;
    %author-detail<email> = $!author-email if $!author-email.defined;
    %author-detail<uri>   = $!author-uri   if $!author-uri.defined;

    my $atom-id = $!id // $!link // Str;
    my %bless = :title($!title // Str), :link($!link // Str),
        :id($atom-id),
        :summary($!summary // Str),
        :author($!author-name // Str),
        :author-detail(%author-detail),
        :content($!content // Str),
        :content-type($!content-type // Str),
        :rights($!rights // Str);
    # Falls back to DateTime.now if not explicitly set; produces
    # non-deterministic XML across separate builder invocations
    %bless<updated>   = $!updated.defined ?? $!updated !! DateTime.now;
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
$e.category("Tech");
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
=item C<author(:$name, :$email, :$uri)> - get/set author details
=item C<category(Str $v?)> - add/get categories
=end pod
