use v6.d;
use XML;
use Syndicate::Item;
use Syndicate::Utils;

unit class Syndicate::Atom::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

has %.author-detail;
has @.categories;
has DateTime $.published;
has Str $.content-type;
has Str $.rights;
has %.source-feed;
has @.contributors;

multi method new(Str $xml) {
    my $doc = XML::Document.new($xml);
    self.new-from-xml($doc.root)
}

multi method new(XML::Element $xml-elem) {
    self.new-from-xml($xml-elem)
}

proto method new-from-xml(|) {*}
multi method new-from-xml(XML::Element $entry-elem) {
    my $id       = get-text($entry-elem, "id");
    my $title    = get-text($entry-elem, "title");
    my $summary  = get-text-optional($entry-elem, "summary");
    my $content  = get-text-optional($entry-elem, "content");
    my $updated  = parse-date-optional(get-text($entry-elem, "updated"));
    my $pub      = parse-date-optional(get-text($entry-elem, "published"));
    my $rights   = get-text-optional($entry-elem, "rights");

    my $link = "";
    with $entry-elem.elements(:TAG<link>)[0] {
        $link = .attribs<href> // "";
    }

    my %author-detail;
    with $entry-elem.elements(:TAG<author>)[0] {
        %author-detail<name>  = get-text-optional($_, "name");
        %author-detail<email> = get-text-optional($_, "email");
        %author-detail<uri>   = get-text-optional($_, "uri");
    }

    my @categories;
    for $entry-elem.elements(:TAG<category>) {
        @categories.push: .attribs<term> // "";
    }

    my @contributors;
    for $entry-elem.elements(:TAG<contributor>) -> $c {
        my %c;
        %c<name>  = get-text-optional($c, "name");
        %c<email> = get-text-optional($c, "email");
        %c<uri>   = get-text-optional($c, "uri");
        @contributors.push: %c;
    }

    my %source-feed;
    with $entry-elem.elements(:TAG<source>)[0] {
        %source-feed<title> = get-text-optional($_, "title");
        %source-feed<id>    = get-text-optional($_, "id");
        with .elements(:TAG<link>)[0] {
            %source-feed<link> = .attribs<href> // "";
        }
        %source-feed<updated> = parse-date-optional(get-text($_, "updated"));
    }

    my $author = %author-detail<name> // %author-detail<email> // Str;

    my %bless = :$id, :$title, :$link, :summary($summary),
        :$author,
        :$content,
        :content-type(get-attrib($entry-elem, "content", "type")),
        :$rights,
        :author-detail(%author-detail),
        :source-feed(%source-feed);
    %bless<updated> = $updated if $updated ~~ DateTime;
    %bless<published> = $pub if $pub ~~ DateTime;
    self.bless(|%bless, :@contributors, :categories(@categories))
}

method XML {
    my $xml = XML::Element.new(:name<entry>);
    $xml.append: XML::Element.new(:name<title>, :nodes([$.title])) if $.title.defined;
    $xml.append: XML::Element.new(:name<link>, :attribs({:href($.link // ""), :rel<alternate>})) if $.link.defined;
    $xml.append: XML::Element.new(:name<id>, :nodes([$.id // $.link // ""])) if $.id.defined || $.link.defined;
    $xml.append: XML::Element.new(:name<summary>, :nodes([$.summary])) if $.summary.defined;

    if $.content.defined {
        my %attribs = :type($.content-type // "text");
        $xml.append: XML::Element.new(:name<content>, :attribs(%attribs), :nodes([encode-entities($.content)]));
    }

    if $.updated.defined {
        $xml.append: XML::Element.new(:name<updated>, :nodes([$.updated.Str]));
    }
    if $.published.defined {
        $xml.append: XML::Element.new(:name<published>, :nodes([$.published.Str]));
    }
    if $.author.defined || %!author-detail {
        my $author = XML::Element.new(:name<author>);
        $author.append: XML::Element.new(:name<name>, :nodes([%!author-detail<name>])) if %!author-detail<name>.defined;
        $author.append: XML::Element.new(:name<email>, :nodes([%!author-detail<email>])) if %!author-detail<email>.defined;
        $author.append: XML::Element.new(:name<uri>, :nodes([%!author-detail<uri>])) if %!author-detail<uri>.defined;
        $xml.append: $author;
    }

    for @.categories -> $cat {
        $xml.append: XML::Element.new(:name<category>, :attribs({:term($cat)}));
    }

    for @.contributors -> %c {
        my $c = XML::Element.new(:name<contributor>);
        $c.append: XML::Element.new(:name<name>, :nodes([%c<name>])) if %c<name>.defined;
        $c.append: XML::Element.new(:name<email>, :nodes([%c<email>])) if %c<email>.defined;
        $c.append: XML::Element.new(:name<uri>, :nodes([%c<uri>])) if %c<uri>.defined;
        $xml.append: $c;
    }

    if %!source-feed {
        my $s = XML::Element.new(:name<source>);
        $s.append: XML::Element.new(:name<title>, :nodes([%!source-feed<title>])) if %!source-feed<title>.defined;
        $s.append: XML::Element.new(:name<id>, :nodes([%!source-feed<id>])) if %!source-feed<id>.defined;
        $s.append: XML::Element.new(:name<link>, :attribs({:href(%!source-feed<link> // ""), :rel<alternate>})) if %!source-feed<link>.defined;
        if %!source-feed<updated>.defined {
            $s.append: XML::Element.new(:name<updated>, :nodes([%!source-feed<updated>.Str]));
        }
        $xml.append: $s;
    }

    $xml.append: XML::Element.new(:name<rights>, :nodes([$.rights])) if $.rights.defined;
    return $xml;
}

method Str(Bool :$pretty = True) { ~self.XML }

=begin pod

=head1 NAME

Syndicate::Atom::Item - Atom 1.0 entry

=head1 SYNOPSIS

=begin code :lang<raku>
my $entry = Syndicate::Atom::Item.new(
    :title("Entry"),
    :id("urn:uuid:abc-123"),
    :link("https://example.com/1"),
    :content("<p>Hello</p>"),
    :content-type("xhtml"),
    :updated(DateTime.now),
);
say ~$entry;
=end code

=head1 DESCRIPTION

An Atom 1.0 entry. Does L<C<Syndicate::Item>|rakudoc:Syndicate::Item>.

=head1 ATTRIBUTES

=item C<$.title>, C<$.link>, C<$.summary>, C<$.author>, C<$.updated> - from Item role
=item C<$.id>, C<$.content> - from Item role
=item C<%.author-detail> - Author hash (name, email, uri)
=item C<@.categories> - Category terms
=item C<$.published> - Published timestamp
=item C<$.content-type> - Content MIME type (e.g. "xhtml", "text")
=item C<$.rights> - Rights text
=item C<%.source-feed> - Source feed hash (title, id, link, updated)
=item C<@.contributors> - Array of contributor hashes

=end pod
