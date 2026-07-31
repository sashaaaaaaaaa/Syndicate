use v6.d;
use XML;
use Syndicate::Item;
use Syndicate::Utils;
use Syndicate::Stats;

unit class Syndicate::Atom::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

submethod TWEAK {
    unless $!updated.defined {
        my $label = $!id.defined ?? $!id !! $!title.defined ?? $!title !! "<unnamed>";
        die "Atom entry '$label' requires an 'updated' timestamp";
    }
    die "Atom entry requires 'id'"   unless $!id.defined   && $!id.chars;
    die "Atom entry requires 'title'" unless $!title.defined && $!title.chars;
}

has Str $.xml-lang;
has %.author-detail of Str;
has @.categories of Str;
has DateTime $.published;
has Str $.content-type;
has Str $.rights;
has %.source-feed;
has @.contributors of Hash;
has @.link-alternate of Hash;
has XML::Element $!cached-xml;
has Lock $!xml-lock = Lock.new;
has Str $!cached-str;
has Lock $!cache-lock = Lock.new;

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    unless $doc {
        Syndicate::Stats.record-error;
        die "Invalid Atom entry XML: $!";
    }
    with-error-recording { self.from-xml($doc.root) }
}

multi method new(XML::Element $xml-elem) {
    with-error-recording { self.from-xml($xml-elem) }
}

method from-xml(XML::Element $entry-elem) {
    my $id       = get-text($entry-elem, "id");
    my $title    = get-text($entry-elem, "title");
    my $summary  = get-text-optional($entry-elem, "summary");
    my $content  = Str;
    my $content-type = Str;
    with $entry-elem.elements(:TAG<content>)[0] -> $ce {
        $content-type = decode-entities($ce.attribs<type> // "text");
        if $content-type eq "xhtml" {
            with $ce.elements[0] -> $xhtml-div {
                $content = ~$xhtml-div;
            }
            # No <div> child (e.g. <content type="xhtml"/>) is a benign empty
            # content — leave $content as Str rather than counting an error.
        } else {
            my $text = decode-entities(element-text($ce));
            $content = $text.defined && $text.chars ?? $text !! Str;
        }
    }
    my $updated  = parse-date(get-text($entry-elem, "updated"));
    my $pub      = parse-date-optional(get-text-optional($entry-elem, "published"));
    my $rights   = get-text-optional($entry-elem, "rights");
    my $lang     = $entry-elem.attribs{'xml:lang'} // Str;

    my @link-alternate;
    my $link = Str;
    for $entry-elem.elements(:TAG<link>) {
        my $rel = .attribs<rel> // "alternate";
        my $href = decode-entities(.attribs<href> // "");
        if $rel eq "alternate" {
            @link-alternate.push: %( href => $href, type => decode-entities(.attribs<type> // Str) );
            $link ||= $href;
        }
    }

    my %author-detail;
    with $entry-elem.elements(:TAG<author>)[0] {
        %author-detail<name>  = get-text-optional($_, "name");
        %author-detail<email> = get-text-optional($_, "email");
        %author-detail<uri>   = get-text-optional($_, "uri");
    }

    my @categories;
    for $entry-elem.elements(:TAG<category>) {
        my $term = decode-entities(.attribs<term> // "");
        @categories.push: $term if $term.chars;
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
            %source-feed<link> = decode-entities(.attribs<href> // "");
        }
        %source-feed<updated> = parse-date-optional(get-text-optional($_, "updated"));
    }

    my $author = %author-detail<name> // %author-detail<email> // Str;

    my %bless = :$id, :$title, :$link, :summary($summary),
        :$author,
        :$content,
        :$content-type,
        :$rights, :xml-lang($lang),
        :author-detail(%author-detail),
        :source-feed(%source-feed);
    %bless<updated> = $updated if $updated ~~ DateTime;
    %bless<published> = $pub if $pub ~~ DateTime;
    my $item = self.bless(|%bless, :@link-alternate, :@contributors, :categories(@categories));
    Syndicate::Stats.record-item;
    $item
}

method XML {
    return $!cached-xml if $!cached-xml.defined;
    $!xml-lock.protect: {
        return $!cached-xml if $!cached-xml.defined;
        my $xml = XML::Element.new(:name<entry>);
        add-attrib($xml, 'xml:lang', $.xml-lang) if $.xml-lang.defined;
        add-element($xml, "title",   $.title);
        if @!link-alternate {
            for @!link-alternate -> %link {
                my %attr = :href(encode-entities(%link<href>)), :rel<alternate>;
                %attr<type> = encode-entities(%link<type>) if %link<type>.defined;
                $xml.append: XML::Element.new(:name<link>, :attribs(%attr));
            }
        } elsif $.link.defined && $.link.chars {
            $xml.append: XML::Element.new(:name<link>, :attribs({:href(encode-entities($.link)), :rel<alternate>}));
        }
        if $.id.defined && $.id.chars {
            add-element($xml, "id", $.id);
        }
        add-element($xml, "summary", $.summary);

        if $.content.defined {
            my %attribs = :type(encode-entities($.content-type // "text"));
            my @nodes;
            if %attribs<type> eq "xhtml" {
                my $xhtml = try { XML::Document.new($.content) };
                my $root = $xhtml ?? $xhtml.root !! Nil;
                my $div  = XML::Element.new(:name<div>, :attribs({:xmlns('http://www.w3.org/1999/xhtml')}));
                if $root.defined && $root.name eq "div" && $root.attribs<xmlns> eq 'http://www.w3.org/1999/xhtml' {
                    $div = $root;
                } elsif $root.defined {
                    $div.nodes = [$root];
                } else {
                    $div.nodes = [encode-entities($.content)];
                }
                @nodes = [$div];
            } else {
                @nodes = [encode-entities($.content)];
            }
            $xml.append: XML::Element.new(:name<content>, :attribs(%attribs), :nodes(@nodes));
        }

        my $upd = $.updated;
        $xml.append: XML::Element.new(:name<updated>, :nodes([$upd.Str]));
        if $.published.defined {
            $xml.append: XML::Element.new(:name<published>, :nodes([$.published.Str]));
        }
        if %!author-detail<name>.defined || %!author-detail<email>.defined || %!author-detail<uri>.defined {
            my $author = XML::Element.new(:name<author>);
            add-element($author, "name",  %!author-detail<name>);
            add-element($author, "email", %!author-detail<email>);
            add-element($author, "uri",   %!author-detail<uri>);
            $xml.append: $author;
        }

        for @.categories -> $cat {
            next unless $cat.defined && $cat.chars;
            $xml.append: XML::Element.new(:name<category>, :attribs({:term(encode-entities($cat))}));
        }

        for @.contributors -> %c {
            my $c = XML::Element.new(:name<contributor>);
            add-element($c, "name",  %c<name>);
            add-element($c, "email", %c<email>);
            add-element($c, "uri",   %c<uri>);
            $xml.append: $c;
        }

        if %!source-feed {
            my $s = XML::Element.new(:name<source>);
            add-element($s, "title", %!source-feed<title>);
            add-element($s, "id",    %!source-feed<id>);
            $s.append: XML::Element.new(:name<link>, :attribs({:href(encode-entities(%!source-feed<link> // "")), :rel<alternate>})) if %!source-feed<link>.defined;
            if %!source-feed<updated>.defined {
                $s.append: XML::Element.new(:name<updated>, :nodes([%!source-feed<updated>.Str]));
            }
            $xml.append: $s;
        }

        add-element($xml, "rights", $.rights);
        $!cached-xml = $xml;
        $xml
    }
}

method Str {
    $!cached-str // $!cache-lock.protect: { $!cached-str //= ~self.XML }
}

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
