use v6.d;
use XML;
use Syndicate::Item;
use Syndicate::Utils;
use Syndicate::Stats;

unit class Syndicate::Atom::Item:ver<0.0.1>:auth<zef:sasha> does Syndicate::Item;

my constant XHTML-NS = 'http://www.w3.org/1999/xhtml';

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
has Bool $.content-is-markup;
has Str $.rights;
has %.source-feed;
has @.contributors of Hash;
has @.link-alternate of Hash;

method to-hash {
    my %h = self.to-hash-common;
    %h<xml-lang>      = $.xml-lang       if $.xml-lang.defined;
    my %author-detail = sanitize(%!author-detail);
    %h<author-detail> = %author-detail   if %author-detail;
    %h<categories>    = @.categories.List if @.categories;
    %h<published>     = $.published.Str  if $.published.defined;
    %h<content-type>  = $.content-type   if $.content-type.defined;
    %h<rights>        = $.rights         if $.rights.defined;
    my %source-feed   = sanitize(%.source-feed);
    %h<source-feed>   = %source-feed     if %source-feed;
    my @contributors  = sanitize(@.contributors);
    %h<contributors>  = @contributors    if @contributors;
    my @link-alternate = sanitize(@.link-alternate);
    %h<link-alternate> = @link-alternate if @link-alternate;
    %h
}

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
    # Index direct children once: per-field elements(:TAG<...>) calls each scan
    # linearly, making a parse O(fields x children). Reads below use the index.
    my @kids = $entry-elem.elements;
    my %child;
    %child{$_.name}.push($_) for @kids;
    my sub idx-text(Str $tag --> Str) {
        my $e = %child{$tag}[0];
        return Str unless $e.defined;
        my $t = element-text($e).trim;
        $t.chars ?? decode-entities($t) !! Str
    }
    my sub idx-required(Str $tag --> Str) {
        my $e = %child{$tag}[0];
        die "Missing required element <$tag> in <{$entry-elem.name}>" without $e;
        my $t = element-text($e).trim;
        die "Empty required element <$tag> in <{$entry-elem.name}>" unless $t.chars;
        decode-entities($t)
    }
    # Optional text of a direct child of a sub-element (author, contributor,
    # source): scans only that element's few children.
    my sub idx-text-on(XML::Element $e, Str $tag --> Str) {
        my $c = $e.elements(:TAG($tag))[0];
        return Str unless $c.defined;
        my $t = element-text($c).trim;
        $t.chars ?? decode-entities($t) !! Str
    }

    my $id       = idx-required("id");
    my $title    = idx-required("title");
    my $summary  = idx-text("summary");
    my $content  = Str;
    my $content-type = Str;
    my $content-is-markup = False;
    with %child<content>[0] -> $ce {
        $content-type = decode-entities($ce.attribs<type> // "text");
        if $content-type eq "xhtml" {
            my @xhtml-divs = $ce.elements;
            if @xhtml-divs {
                # Normalize to the div-wrapped form the generator emits, so a
                # bare single child (e.g. <p>) roundtrips byte-stably instead
                # of gaining a wrapper only on the second pass.
                if @xhtml-divs.elems == 1 {
                    my $only = @xhtml-divs[0];
                    if $only.name eq "div" && $only.attribs<xmlns> eq XHTML-NS {
                        $content = ~$only;
                    } else {
                        $content = '<div xmlns="' ~ XHTML-NS ~ '">' ~ ~$only ~ '</div>';
                    }
                } else {
                    # Keep all child elements — a lenient feed with several
                    # sibling <div>s must not lose all but the first.
                    $content = @xhtml-divs.map(~*).join;
                }
            }
            # No element child (e.g. <content type="xhtml"/>) is a benign empty
            # content — leave $content as Str rather than counting an error.
        } else {
            # Preserve inline markup for element-form bodies; text-only bodies
            # (entity-encoded markup, CDATA) stay decoded plain text.
            ($content, $content-is-markup) = content-and-markup($ce);
        }
    }
    my $updated  = parse-date(idx-required("updated"));
    my $pub      = parse-date-optional(idx-text("published"));
    my $rights   = idx-text("rights");
    my $lang     = $entry-elem.attribs{'xml:lang'} // Str;

    my @link-alternate;
    my $link = Str;
    for @(%child<link> // []) {
        my $rel = .attribs<rel> // "alternate";
        my $href = decode-entities(.attribs<href> // "");
        if $rel eq "alternate" {
            @link-alternate.push: %( href => $href, type => decode-entities(.attribs<type> // Str) );
            $link ||= $href;
        }
    }

    my %author-detail;
    with %child<author>[0] {
        %author-detail<name>  = idx-text-on($_, "name");
        %author-detail<email> = idx-text-on($_, "email");
        %author-detail<uri>   = idx-text-on($_, "uri");
    }

    my @categories;
    for @(%child<category> // []) {
        my $term = decode-entities(.attribs<term> // "");
        @categories.push: $term if $term.chars;
    }

    my @contributors;
    for @(%child<contributor> // []) -> $c {
        my %c;
        %c<name>  = idx-text-on($c, "name");
        %c<email> = idx-text-on($c, "email");
        %c<uri>   = idx-text-on($c, "uri");
        @contributors.push: %c;
    }

    my %source-feed;
    with %child<source>[0] {
        %source-feed<title> = idx-text-on($_, "title");
        %source-feed<id>    = idx-text-on($_, "id");
        with .elements(:TAG<link>)[0] {
            %source-feed<link> = decode-entities(.attribs<href> // "");
        }
        %source-feed<updated> = parse-date-optional(idx-text-on($_, "updated"));
    }

    my $author = %author-detail<name> // %author-detail<email> // Str;

    my %bless = :$id, :$title, :$link, :summary($summary),
        :$author,
        :$content,
        :$content-type,
        :content-is-markup($content-is-markup),
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
                my $div  = XML::Element.new(:name<div>, :attribs({:xmlns(XHTML-NS)}));
                if $xhtml {
                    my $root = $xhtml.root;
                    if $root.name eq "div" && $root.attribs<xmlns> eq XHTML-NS {
                        $div = $root;
                    } else {
                        $div.nodes = [$root];
                    }
                    @nodes = [$div];
                } else {
                    # A lenient parse can leave several sibling elements (e.g.
                    # two <div>s) that are not a well-formed single document —
                    # keep them all as siblings rather than dropping any.
                    my $frag = try { XML::Document.new("<wrap>{$.content}</wrap>") };
                    my @children = $frag ?? @($frag.root.elements) !! [];
                    if @children {
                        @nodes = @children;
                    } else {
                        $div.nodes = [encode-entities($.content)];
                        @nodes = [$div];
                    }
                }
            } elsif $.content-is-markup {
                # Element-form content (parsed from real markup) regenerates as
                # markup; unparseable bodies fall back to encoded text.
                my @nodes2 = markup-nodes($.content);
                @nodes = @nodes2 ?? @nodes2 !! [encode-entities($.content)];
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
=item C<$.content-is-markup> - True when the body held raw element markup
    (an html-typed C<content> element with element children); C<$.content>
    then holds that markup, which round-trips on regeneration
=item C<$.rights> - Rights text
=item C<%.source-feed> - Source feed hash (title, id, link, updated)
=item C<@.contributors> - Array of contributor hashes

=end pod
