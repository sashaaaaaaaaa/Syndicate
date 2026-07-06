use v6.d;
use XML;
use Syndicate::Feed;
use Syndicate::Atom::Item;
use Syndicate::Utils;

my constant NS-ATOM = 'http://www.w3.org/2005/Atom';
use Syndicate::Stats;

unit class Syndicate::Atom:ver<0.0.1>:auth<zef:sasha> does Syndicate::Feed;

has Str $.id;
has Str $.subtitle;
has Str $.author;
has %.author-detail of Str;
has @.categories of Str;
has DateTime $.updated;
has Str $.rights;
has Str $.icon;
has Str $.logo;
has @.contributors of Hash;
has %.link-self of Str;
has %.link-alternate of Str;
    has DateTime $!computed-updated;
    has XML::Element $!cached-xml;
    has Lock $!xml-lock = Lock.new;

submethod TWEAK {
    self!cache-updated;
}

multi method new(XML::Document $doc) {
    my $feed = $doc.root;
    die "Not an Atom feed" unless $feed.name eq "feed";

    my $id    = get-text($feed, "id");
    my $title = get-text($feed, "title");
    my $desc  = get-text-optional($feed, "subtitle");
    my $rights = get-text-optional($feed, "rights");
    my $gen      = get-text-optional($feed, "generator");
    my $icon     = get-text-optional($feed, "icon");
    my $logo     = get-text-optional($feed, "logo");
    my $lang     = $feed.attribs{'xml:lang'} // Str;
    my $upd      = parse-date(get-text($feed, "updated"));

    my %author-detail;
    with $feed.elements(:TAG<author>)[0] {
        %author-detail<name>  = get-text-optional($_, "name");
        %author-detail<email> = get-text-optional($_, "email");
        %author-detail<uri>   = get-text-optional($_, "uri");
    }

    my @categories;
    for $feed.elements(:TAG<category>) {
        @categories.push: .attribs<term> // "";
    }

    my @contributors;
    for $feed.elements(:TAG<contributor>) -> $c {
        my %c;
        %c<name>  = get-text-optional($c, "name");
        %c<email> = get-text-optional($c, "email");
        %c<uri>   = get-text-optional($c, "uri");
        @contributors.push: %c;
    }

    my %link-self;
    my %link-alternate;
    my $primary-link = Str;
    for $feed.elements(:TAG<link>) {
        my $rel = .attribs<rel> // "alternate";
        my $href = .attribs<href> // "";
        if $rel eq "self" {
            %link-self = (href => $href, type => .attribs<type> // Str);
        }
        elsif $rel eq "alternate" {
            %link-alternate = (href => $href, type => .attribs<type> // Str);
            $primary-link = $href unless $primary-link;
        }
    }
    $primary-link ||= %link-self<href>;

    my @items;
    for $feed.elements(:TAG<entry>) -> $entry-elem {
        @items.push: Syndicate::Atom::Item.from-xml($entry-elem);
    }

    my $author = %author-detail<name> // %author-detail<email> // Str;

    my %bless = :$id, :$title, :link($primary-link),
        :description($desc),
        :subtitle($desc), :$rights,
        :$author, :language($lang),
        :generator($gen), :$icon, :$logo,
        :author-detail(%author-detail),
        :link-self(%link-self), :link-alternate(%link-alternate);
    %bless<updated> = $upd if $upd ~~ DateTime;
    CATCH {
        Syndicate::Stats.record-error;
        .rethrow;
    }
    self.bless(|%bless, :@items, :@contributors, :categories(@categories))
}

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    unless $doc {
        Syndicate::Stats.record-error;
        die "Invalid Atom XML: $!";
    }
    self.new($doc)
}

method !cache-updated {
    $!computed-updated = $!updated;
    unless $!computed-updated.defined {
        for @!items -> $item {
            with $item.updated {
                $!computed-updated = $_ if !$!computed-updated.defined || $_ > $!computed-updated;
            }
        }
    }
    die "Atom feed requires 'updated' timestamp" without $!computed-updated;
}

method XML {
    $!xml-lock.protect: {
        return $!cached-xml if $!cached-xml.defined;
        my $xml = XML::Element.new(:name<feed>, :attribs({:xmlns(NS-ATOM)}));
        $xml.attribs{'xml:lang'} = $.language if $.language.defined;
        add-element($xml, "id",        $.id);
        add-element($xml, "title",     $.title);
        add-element($xml, "subtitle",  $.subtitle);

        if $.link.defined {
            $xml.append: XML::Element.new(:name<link>, :attribs({:href(encode-entities($.link)), :rel<alternate>}));
        }
        if %!link-self<href>.defined {
            my %attr = :href(encode-entities(%!link-self<href>)), :rel<self>;
            %attr<type> = %!link-self<type> if %!link-self<type>.defined;
            $xml.append: XML::Element.new(:name<link>, :attribs(%attr));
        }

        if %!author-detail<name>.defined || %!author-detail<email>.defined || %!author-detail<uri>.defined {
            my $author = XML::Element.new(:name<author>);
            add-element($author, "name",  %!author-detail<name>);
            add-element($author, "email", %!author-detail<email>);
            add-element($author, "uri",   %!author-detail<uri>);
            $xml.append: $author;
        }

        add-element($xml, "rights",    $.rights);
        add-element($xml, "generator", $.generator);
        add-element($xml, "icon",      $.icon);
        add-element($xml, "logo",      $.logo);

        for @.categories -> $cat {
            $xml.append: XML::Element.new(:name<category>, :attribs({:term($cat)}));
        }

        for @.contributors -> %c {
            my $c = XML::Element.new(:name<contributor>);
            add-element($c, "name",  %c<name>);
            add-element($c, "email", %c<email>);
            add-element($c, "uri",   %c<uri>);
            $xml.append: $c;
        }

        my $upd = $!computed-updated;
        $xml.append: XML::Element.new(:name<updated>, :nodes([$upd.Str]));

        $xml.append: $_.XML for @.items;

        $!cached-xml = $xml;
        $xml
    }
}

=begin pod

=head1 NAME

Syndicate::Atom - Atom 1.0 feed

=head1 SYNOPSIS

=begin code :lang<raku>
my $feed = Syndicate::Atom.new($xml-string);
my $feed = Syndicate::Atom.new(:title("My Feed"), :id("urn:uuid:..."), ...);
say ~$feed;
=end code

=head1 DESCRIPTION

Parses and generates Atom 1.0 feeds. Does L<C<Syndicate::Feed>|rakudoc:Syndicate::Feed>.

=head1 ATTRIBUTES

=item C<$.title>, C<$.link>, C<$.description> - from Feed role (description → subtitle)
=item C<$.generator>, C<$.language> - from Feed role
=item C<$.id> - Atom feed ID
=item C<$.subtitle> - Feed subtitle
=item C<%.author-detail> - Author hash (name, email, uri)
=item C<@.categories> - Category terms
=item C<$.updated> - Last updated timestamp
=item C<$.rights> - Rights/license text
=item C<$.icon> - Feed icon URL
=item C<$.logo> - Feed logo URL
=item C<@.contributors> - Array of contributor hashes
=item C<%.link-self> - Self link hash (href, type)
=item C<%.link-alternate> - Alternate link hash (href, type)

=end pod
