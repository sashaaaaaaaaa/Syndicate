use v6.d;
use HTTP::Tiny;
use URI;
use Syndicate::Parse;

my constant $link-tag = rx/ '<link' [.|\n]*? ['/>' | '>'] /;
my constant $base-tag = rx/ '<base' [.|\n]*? ['/>' | '>'] /;

unit class Syndicate::Discovery:ver<0.0.1>:auth<zef:sasha>;

method fetch(Str $url, Int :$max-redirects = 5, Int :$timeout = 30) {
    my $ua = HTTP::Tiny.new(:$max-redirects, :$timeout);
    my $resp = $ua.get($url);
    die "HTTP {$resp<status>} - {$resp<reason>}" unless $resp<success>;
    my $body = $resp<content>.decode;
    parse-feed($body)
}

method discover(Str $url, Int :$max-redirects = 5, Int :$timeout = 30) {
    my $ua = HTTP::Tiny.new(:$max-redirects, :$timeout);
    my $resp = $ua.get($url);
    die "HTTP {$resp<status>} - {$resp<reason>}" unless $resp<success>;
    my $body = $resp<content>.decode;

    my $format;
    try { $format = feed-format($body) };
    return parse-feed($body) if $format.defined;

    my @feeds = self.find-feeds($body, $url);
    die "No feeds found at $url" unless @feeds;
    self.fetch(@feeds[0])
}

method find-feeds(Str $html, Str $base-url --> Array) {
    my @feeds;
    my $base = self.base-url($html) // $base-url;

    for $html.comb($link-tag) -> $tag {
        my %attr = self!parse-attrs($tag);
        next unless %attr<rel> && %attr<rel>.lc eq 'alternate';
        my $tv = (%attr<type> // "").lc;
        next unless $tv eq 'application/rss+xml'
                  || $tv eq 'application/atom+xml'
                  || $tv eq 'application/feed+json';
        next unless %attr<href>.defined;
        @feeds.push: self.resolve-url(%attr<href>, $base);
    }
    @feeds
}

method !parse-attrs(Str $tag --> Map) {
    my %attrs;
    for $tag.match(/:i (\w+) \s* '=' \s* ( \" <-["]>* \" || \' <-[']>* \' || \S+ ) /, :global) -> $m {
        my $name = ~$m[0];
        my $raw  = ~$m[1];
        my $val  = $raw;
        if $raw.starts-with('"') && $raw.ends-with('"') {
            $val = $raw.substr(1, $raw.chars - 2);
        } elsif $raw.starts-with("'") && $raw.ends-with("'") {
            $val = $raw.substr(1, $raw.chars - 2);
        }
        %attrs{$name.lc} = $val;
    }
    %attrs
}

method base-url(Str $html --> Str) {
    with $html.comb($base-tag)[0] -> $tag {
        my %attr = self!parse-attrs($tag);
        return %attr<href> if %attr<href>.defined;
    }
    Str
}

method resolve-url(Str $url, Str $base --> Str) {
    return $url if $url ~~ /^https?\:\/\//;
    my $scheme = $base ~~ /^(https?)/ ?? ~$0 !! 'https';
    return $scheme ~ ':' ~ $url if $url ~~ /^\/\//;

    my $b = URI.new($base);
    my $u = URI.new($url);
    my $rp = $u.path.path;
    unless $rp.starts-with('/') {
        my $bp = $b.path.path;
        $bp ~~ s/ <-[/]>* $ // unless $bp.ends-with('/');
        $rp = $bp ~ $rp;
    }
    my $port = $b.port;
    my $port-str = $port.defined ?? ($port == 80 || $port == 443 ?? "" !! ":$port") !! "";
    my $result = $b.scheme ~ '://' ~ $b.host ~ $port-str ~ $rp;
    $result ~= '?' ~ $u.query.Str if $u.query.Str.chars;
    $result ~= '#' ~ $u.fragment  if $u.fragment.defined && $u.fragment.chars;
    $result
}

=begin pod

=head1 NAME

Syndicate::Discovery - Feed URL discovery and fetching

=head1 SYNOPSIS

=begin code :lang<raku>
use Syndicate::Discovery;

my $disc = Syndicate::Discovery.new;
my $feed = $disc.fetch("https://example.com/feed.xml");
my $feed = $disc.discover("https://example.com");
my @urls = $disc.find-feeds($html, $base-url);
=end code

=head1 DESCRIPTION

Fetches feeds from URLs and discovers feed URLs from HTML pages.
Parses C<E<lt>linkE<gt>> tags with C<rel="alternate"> for
RSS, Atom, and JSON Feed content types.

=head1 METHODS

=head2 C<fetch(Str $url, Int :$max-redirects = 5, Int :$timeout = 30)>

Fetches a URL and parses the feed. Dies on HTTP errors.

=head2 C<discover(Str $url, Int :$max-redirects = 5, Int :$timeout = 30)>

Fetches a URL, tries to parse as a feed. If that fails, searches the HTML
for C<E<lt>linkE<gt>> feed tags and fetches the first discovered feed URL.

=head2 C<find-feeds(Str $html, Str $base-url --> Array)>

Returns an array of feed URLs found in HTML by scanning C<E<lt>linkE<gt>>
tags with C<rel="alternate"> and appropriate type attributes.

=end pod
