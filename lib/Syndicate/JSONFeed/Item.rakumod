use v6.d;
use Syndicate::Item;
use Syndicate::Utils;
use Syndicate::Stats;

unit class Syndicate::JSONFeed::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

has Str $.external_url;
has Str $.content_html;
has Str $.content_text;
has Str $.image;
has Str $.banner_image;
has DateTime $.date_published;
has DateTime $.date_modified;
has @.authors of Hash;
has @.tags of Str;

method new-from-hash(%h) {
    my $title   = %h<title> // Str;
    my $link    = %h<url> // %h<external_url> // Str;
    my $summary = %h<summary> // Str;
    my $id      = %h<id> // $link // Str;

    my $dp = parse-date-optional(%h<date_published> // Str);
    my $dm = parse-date-optional(%h<date_modified> // Str);
    my $author = Str;

    my @authors;
    with %h<authors> -> $a {
        for @$a {
            @authors.push: %(
                name   => .<name> // Str,
                url    => .<url> // Str,
                avatar => .<avatar> // Str,
            )
        }
        $author = @authors[0]<name> // $author;
    }

    my @tags;
    @tags = @(%h<tags>) if %h<tags>:exists;

    my $content = %h<content_html> // %h<content_text> // Str;
    my %bless = :$title, :$link, :summary($summary),
        :$id,
        :$content,
        :external_url(%h<external_url> // Str),
        :content_html(%h<content_html> // Str),
        :content_text(%h<content_text> // Str),
        :image(%h<image> // Str),
        :banner_image(%h<banner_image> // Str),
        :$author;
    %bless<date_published> = $dp if $dp ~~ DateTime;
    %bless<date_modified>  = $dm if $dm ~~ DateTime;
    Syndicate::Stats.record-item;
    self.bless(|%bless, :@authors, :@tags)
}

method to-hash {
    my %h;
    %h<title>          = $.title         if $.title.defined;
    %h<url>            = $.link          if $.link.defined;
    %h<external_url>   = $.external_url  if $.external_url.defined;
    %h<summary>        = $.summary       if $.summary.defined;
    %h<id>             = $.id            if $.id.defined;
    %h<content_html>   = $.content_html  if $.content_html.defined;
    %h<content_text>   = $.content_text  if $.content_text.defined;
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
        %h<tags> = @.tags.Array;
    }
    %h
}

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
