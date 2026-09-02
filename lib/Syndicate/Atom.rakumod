use v6.d;
use XML;
use Syndicate::Feed;
use Syndicate::Atom::Item;
use Syndicate::Utils;

use Syndicate::Stats;

unit class Syndicate::Atom:ver<0.0.6>:auth<zef:sasha> does Syndicate::Feed;

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
has @.link-self of Hash;
has @.link-alternate of Hash;
has @.extra-links of Hash;
has DateTime $!computed-updated;

method to-hash(:$clone = True) {
    my %h = self.to-hash-common(:$clone);
    %h<id>            = $.id            if $.id.defined;
    # Mirror the computed updated emitted by XML(): the newest timestamp
    # among the feed's own updated and its entries (floored at $.updated),
    # without dying when no timestamp exists anywhere.
    with self!latest-updated {
        %h<updated> = $_.Str;
    }
    %h<subtitle>      = $.subtitle      if $.subtitle.defined;
    %h<rights>        = $.rights        if $.rights.defined;
    %h<icon>          = $.icon          if $.icon.defined;
    %h<logo>          = $.logo          if $.logo.defined;
    my %author-detail = sanitize(%!author-detail);
    %h<author-detail> = %author-detail  if %author-detail;
    my @categories    = sanitize(@.categories);
    %h<categories>    = @categories     if @categories;
    my @contributors  = sanitize(@.contributors);
    %h<contributors>  = @contributors   if @contributors;
    my @link-self     = sanitize(@.link-self);
    %h<link-self>     = @link-self      if @link-self;
    my @link-alternate = sanitize(@.link-alternate);
    %h<link-alternate> = @link-alternate if @link-alternate;
    my @extra-links   = sanitize(@.extra-links);
    %h<extra-links>   = @extra-links    if @extra-links;
    %h
}
has XML::Element $!cached-xml;
has Lock $!xml-lock = Lock.new;

multi method new(XML::Document $doc) {
    with-error-recording {
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
        # Feed-level updated is optional on input: when absent (or invalid),
        # !latest-updated computes it from the newest entry timestamp, and
        # XML()/to-hash emit that. Fully timestamp-less feeds still die in
        # !cache-updated.
        my $upd      = parse-date(:optional, get-text-optional($feed, "updated"));

        my %author-detail;
        with $feed.elements(:TAG<author>)[0] {
            %author-detail<name>  = get-text-optional($_, "name");
            %author-detail<email> = get-text-optional($_, "email");
            %author-detail<uri>   = get-text-optional($_, "uri");
        }

        my @categories;
        for $feed.elements(:TAG<category>) {
            my $term = decode-entities(.attribs<term> // "");
            @categories.push: $term if $term.chars;
        }

        my @contributors;
        for $feed.elements(:TAG<contributor>) -> $c {
            my %c;
            %c<name>  = get-text-optional($c, "name");
            %c<email> = get-text-optional($c, "email");
            %c<uri>   = get-text-optional($c, "uri");
            @contributors.push: %c;
        }

        my @link-self;
        my @link-alternate;
        my @extra-links;
        my $primary-link = Str;
        for $feed.elements(:TAG<link>) {
            my $rel = .attribs<rel> // "alternate";
            my $href = decode-entities(.attribs<href> // "");
            if $rel eq "self" {
                @link-self.push: %( href => $href, type => decode-entities(.attribs<type> // Str) );
            }
            elsif $rel eq "alternate" {
                @link-alternate.push: %( href => $href, type => decode-entities(.attribs<type> // Str) );
                $primary-link ||= $href;
            } else {
                @extra-links.push: %( rel => $rel, href => $href, type => decode-entities(.attribs<type> // Str) );
            }
        }
        # A feed with only a self link has no home-page URL: do not fall back
        # to the self href, or generation would emit a bogus alternate link.

        my @items;
        for $feed.elements(:TAG<entry>) -> $entry-elem {
            # Match the RSS 0.91/1.0 policy: an entry that fails its own
            # required-field checks is skipped with one recorded error
            # rather than aborting the whole feed.
            my $item = try { Syndicate::Atom::Item.from-xml($entry-elem) };
            if $item.defined {
                @items.push: $item;
            } else {
                Syndicate::Stats.record-error;
            }
        }

        my $author = %author-detail<name> // %author-detail<email> // Str;

        my %bless = :$id, :$title, :link($primary-link),
            :description($desc),  # Feed role expects $.description
            :subtitle($desc),     # Atom expects subtitle; same value intentionally
            :$rights,
            :$author, :language($lang),
            :generator($gen), :$icon, :$logo,
            :author-detail(%author-detail);
        %bless<updated> = $upd if $upd ~~ DateTime;
        self.bless(|%bless, :@items, :@contributors, :categories(@categories),
                   :@link-self, :@link-alternate, :@extra-links)
    }
}

multi method new(Str $xml) {
    my $doc = try { XML::Document.new($xml) };
    unless $doc {
        Syndicate::Stats.record-error;
        die "Invalid Atom XML: $!";
    }
    self.new($doc)
}

method !latest-updated {
    my $computed = $!computed-updated;
    unless $computed.defined {
        $computed = $!updated;
        for @!items -> $item {
            with $item.updated {
                $computed = $_ if !$computed.defined || $_ > $computed;
            }
        }
    }
    $computed
}

method !cache-updated {
    $!computed-updated = self!latest-updated;
    die "Atom feed requires 'updated' timestamp" without $!computed-updated;
}

method XML {
    return $!cached-xml if $!cached-xml.defined;
    $!xml-lock.protect: {
        return $!cached-xml if $!cached-xml.defined;
        self!cache-updated;
        my $xml = XML::Element.new(:name<feed>, :attribs({:xmlns(NS-ATOM)}));
        add-attrib($xml, 'xml:lang', $.language) if $.language.defined;
        add-element($xml, "id",        $.id);
        add-element($xml, "title",     $.title);
        add-element($xml, "subtitle",  $.subtitle);

        if @!link-alternate {
            for @!link-alternate -> %link {
                my %link-attr = :href(encode-entities(%link<href>)), :rel<alternate>;
                %link-attr<type> = encode-entities(%link<type>) if %link<type>.defined;
                $xml.append: XML::Element.new(:name<link>, :attribs(%link-attr));
            }
        } elsif $.link.defined && $.link.chars {
            $xml.append: XML::Element.new(:name<link>, :attribs({:href(encode-entities($.link)), :rel<alternate>}));
        }
        if @!link-self {
            for @!link-self -> %link {
                my %attr = :href(encode-entities(%link<href>)), :rel<self>;
                %attr<type> = encode-entities(%link<type>) if %link<type>.defined;
                $xml.append: XML::Element.new(:name<link>, :attribs(%attr));
            }
        }
        if @!extra-links {
            for @!extra-links -> %link {
                my %attr = :href(encode-entities(%link<href>));
                %attr<rel>  = encode-entities(%link<rel>)  if %link<rel>.defined;
                %attr<type> = encode-entities(%link<type>) if %link<type>.defined;
                $xml.append: XML::Element.new(:name<link>, :attribs(%attr));
            }
        }

        if %!author-detail<name>.defined || %!author-detail<email>.defined || %!author-detail<uri>.defined {
            my $author = XML::Element.new(:name<author>);
            add-element($author, "name",  %!author-detail<name>);
            add-element($author, "email", %!author-detail<email>);
            add-element($author, "uri",   %!author-detail<uri>);
            $xml.append: $author;
        } elsif $.author.defined && $.author.chars {
            my $author = XML::Element.new(:name<author>);
            add-element($author, "name", $.author);
            $xml.append: $author;
        }

        add-element($xml, "rights",    $.rights);
        add-element($xml, "generator", $.generator);
        add-element($xml, "icon",      $.icon);
        add-element($xml, "logo",      $.logo);

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
=item C<@.link-self> - Self link hashes (href, type)
=item C<@.link-alternate> - Alternate link hashes (href, type)

=head1 updated DIVERGENCE

Atom requires an C<updated> timestamp, so C<XML()>/C<Str()> die when neither
the feed nor any entry carries one. C<to-hash()> is intentionally lenient for
inspection: it simply omits the C<updated> key in that case rather than
throwing, mirroring the computed value (newest entry timestamp) when one exists.

=end pod
