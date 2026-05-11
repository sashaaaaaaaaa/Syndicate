use v6.d;
use Syndicate::RSS::Item;
use Syndicate::Atom::Item;
use Syndicate::RSS::V0_91::Item;

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
    my $guid = $!id // $!link // Str;
    my %bless = :title($!title // Str), :link($!link // Str),
        :summary($!summary // Str),
        :author($!author-name // Str),
        :$guid;
    %bless<updated> = $!updated if $!updated ~~ DateTime;
    %bless<category> = @!categories[0] if @!categories;
    Syndicate::RSS::Item.new(|%bless)
}

method build-v0_91-item {
    my %bless = :title($!title // Str), :link($!link // Str),
        :summary($!summary // Str);
    Syndicate::RSS::V0_91::Item.new(|%bless)
}

method build-atom-item {
    my %author-detail;
    %author-detail<name>  = $!author-name  if $!author-name.defined;
    %author-detail<email> = $!author-email if $!author-email.defined;
    %author-detail<uri>   = $!author-uri   if $!author-uri.defined;

    my $atom-id = $!id // $!link // "";
    my %bless = :title($!title // Str), :link($!link // Str),
        :id($atom-id),
        :summary($!summary // Str),
        :author($!author-name // Str),
        :author-detail(%author-detail),
        :content($!content // Str),
        :content-type($!content-type // Str),
        :rights($!rights // Str);
    %bless<updated>   = $!updated   if $!updated ~~ DateTime;
    %bless<published> = $!published if $!published ~~ DateTime;
    my @cats = @!categories;
    Syndicate::Atom::Item.new(|%bless, :categories(@cats))
}
