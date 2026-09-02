use v6.d;
use JSON::Fast;
use Syndicate::Item;
use Syndicate::Utils;
use Syndicate::Stats;

sub str-field(%h, Str $name --> Str) {
    my $v = %h{$name}:exists ?? %h{$name} // Str !! Str;
    die "JSON Feed Item '$name' must be a string, got {$v.^name}" unless $v ~~ Str;
    $v
}

unit class Syndicate::JSONFeed::Item:ver<0.0.5>:auth<zef:sasha> does Syndicate::Item;

multi method new(Str $json) {
    my %h;
    my $ok = try { %h = from-json($json); True };
    unless $ok {
        Syndicate::Stats.record-error;
        die "Invalid JSON Feed item JSON: $!";
    }
    self.new-from-hash(%h)
}

has Str $.external_url;
has Str $.content_html;
has Str $.content_text;
has Str $.image;
has Str $.banner_image;
has DateTime $.date_published;
has DateTime $.date_modified;
has @.authors of Hash;
has @.tags of Str;
has Str $!cached-str;
has Hash $!cached-hash;
has Lock $!cache-lock = Lock.new;
has Lock $!hash-lock = Lock.new;

multi method new-from-hash(%h) {
    my $title   = str-field(%h, 'title');
    my $link    = str-field(%h, 'url');
    my $summary = str-field(%h, 'summary');
    my $id      = %h<id>.defined ?? str-field(%h, 'id') !! $link;
    die "JSON Feed Item requires id or url" unless $id.defined && $id.chars;

    my $dp = parse-date(:optional, %h<date_published>);
    my $dm = parse-date(:optional, %h<date_modified>);
    my $author = Str;

    my @authors;
    with %h<authors> -> $a {
        die "JSON Feed Item 'authors' must be an array, got {$a.^name}" unless $a ~~ Array;
        for @$a {
            die "JSON Feed Item 'authors' elements must be objects, got {$_.^name}" unless $_ ~~ Hash;
            @authors.push: %(
                name   => .<name> // Str,
                url    => .<url> // Str,
                avatar => .<avatar> // Str,
            )
        }
        $author = @authors[0]<name> // $author;
    }

    my @tags;
    with %h<tags> -> $t {
        die "JSON Feed Item 'tags' must be an array, got {$t.^name}" unless $t ~~ Positional;
        for @$t -> $tag {
            die "JSON Feed Item 'tags' elements must be strings, got {$tag.^name}" unless $tag ~~ Str;
            @tags.push: $tag;
        }
    }

    my $externalUrl = str-field(%h, 'external_url');
    my $contentHtml = str-field(%h, 'content_html');
    my $contentText = str-field(%h, 'content_text');
    my $image       = str-field(%h, 'image');
    my $bannerImage = str-field(%h, 'banner_image');
    my $content = $contentHtml.defined && $contentHtml.chars
        ?? $contentHtml
        !! $contentText.defined && $contentText.chars
            ?? $contentText
            !! Str;
    my %bless = :$title, :$link, :summary($summary),
        :$id,
        :$content,
        :external_url($externalUrl),
        :content_html($contentHtml),
        :content_text($contentText),
        :image($image),
        :banner_image($bannerImage),
        :$author;
    %bless<date_published> = $dp if $dp ~~ DateTime;
    %bless<date_modified>  = $dm if $dm ~~ DateTime;
    %bless<updated>        = $dm if $dm ~~ DateTime;
    my $item = self.bless(|%bless, :@authors, :@tags);
    Syndicate::Stats.record-item;
    $item
}

method to-hash {
    $!hash-lock.protect: {
        $!cached-hash //= do {
            my %h;
            %h<title>          = $.title         if $.title.defined;
            %h<url>            = $.link          if $.link.defined;
            %h<external_url>   = $.external_url  if $.external_url.defined;
            %h<summary>        = $.summary       if $.summary.defined;
            %h<id>             = $.id            if $.id.defined;
            %h<content_html> = $.content_html  if $.content_html.defined;
            %h<content_text>  = $.content_text  if $.content_text.defined;
            # Fallback: if neither content_html nor content_text was
            # explicitly stored, use $.content as content_html
            unless $.content_html.defined || $.content_text.defined {
                %h<content_html> //= $.content if $.content.defined;
            }
            %h<image>          = $.image         if $.image.defined;
            %h<banner_image>   = $.banner_image  if $.banner_image.defined;
            %h<date_published> = $.date_published.Str if $.date_published.defined;
            %h<date_modified>  = $.date_modified.Str  if $.date_modified.defined;
            if @.authors {
                %h<authors> = @.authors.map({
                    my %a;
                    %a<name>   = .<name>   if .<name>.defined;
                    %a<url>    = .<url>    if .<url>.defined;
                    %a<avatar> = .<avatar> if .<avatar>.defined;
                    %a
                }).Array;
            }
            if @.tags {
                %h<tags> = @.tags.clone;
            }
            %h
        }
        my %h = %($!cached-hash);
        %h<authors> = %h<authors>.map(*.clone).Array if %h<authors>:exists;
        %h<tags> = %h<tags>.clone if %h<tags>:exists;
        %h
    }
}

method Str { $!cache-lock.protect: { $!cached-str //= to-json $.to-hash } }

=begin pod

=head1 NAME

Syndicate::JSONFeed::Item - JSON Feed item

=head1 SYNOPSIS

=begin code :lang<raku>
my $item = Syndicate::JSONFeed::Item.new-from-hash(%json-hash);
my %h = $item.to-hash;
=end code

=head1 DESCRIPTION

A JSON Feed item. Does L<C<Syndicate::Item>|rakudoc:Syndicate::Item>.

=head1 ATTRIBUTES

=item C<$.title>, C<$.link>, C<$.summary>, C<$.author> - from Item role
=item C<$.id>, C<$.content> - from Item role
=item C<$.external_url> - External URL
=item C<$.content_html> - Content as HTML
=item C<$.content_text> - Content as plain text
=item C<$.image> - Image URL
=item C<$.banner_image> - Banner image URL
=item C<$.date_published> - Published timestamp
=item C<$.date_modified> - Modified timestamp
=item C<@.authors> - Array of author hashes
=item C<@.tags> - Array of tag strings

=end pod
