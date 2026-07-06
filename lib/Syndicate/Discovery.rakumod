use v6.d;
use HTTP::Tiny;
use URI;
use Syndicate::Parse;
use Syndicate::Utils;

# Pragmatic regex for common-case feed discovery from typical HTML pages.
# Not a full HTML parser — will match inside comments, <script>/<style> blocks,
# and may break on unusual attribute quoting. Acceptable for the use case.
my constant $link-tag = rx:i/ '<link' <-[>]>* ['/>' | '>'] /;
my constant $base-tag = rx:i/ '<base' <-[>]>* ['/>' | '>'] /;

unit class Syndicate::Discovery:ver<0.0.1>:auth<zef:sasha>;

has HTTP::Tiny $.ua is built(False);

submethod BUILD(Int :$max-redirects = 5, Int :$timeout = 30, :$ua) {
    with $ua { $!ua = $_ }
    $!ua //= HTTP::Tiny.new(:$max-redirects, :$timeout);
}

method !decode-response($resp --> Str) {
    my $charset = 'utf-8';
    with $resp<headers><content-type>.[0] {
        for .lc.split(';') {
            .trim ~~ /^charset\s* \= \s* (<[^\s;]>+)/ and $charset = ~$0.subst(/<[\'\"]>/, '', :g);
        }
    }
    $resp<content>.decode($charset)
}

method !validate-url(Str $url) {
    my $scheme = try { URI.new($url).scheme.lc };
    die "Blocked URL scheme — only http and https are permitted"
        unless $scheme.defined && ($scheme eq 'http' || $scheme eq 'https');
}

method fetch(Str $url --> Syndicate::Feed:D) {
    self!validate-url($url);
    my $resp = $.ua.get($url);
    die "HTTP {$resp<status>} - {$resp<reason> // ''}" unless $resp<success>;
    my $ct = $resp<headers><content-type>.[0] // '';
    die "Not a feed — Content-Type: $ct" unless $ct.lc.contains('xml') || $ct.lc.contains('json') || $ct.lc.contains('html') || $ct.lc.contains('rss') || $ct.lc.contains('atom') || $ct.lc.contains('feed');
    my $body = self!decode-response($resp);
    parse-feed($body)
}

method discover(Str $url --> Syndicate::Feed:D) {
    self!validate-url($url);
    my $resp = $.ua.get($url);
    die "HTTP {$resp<status>} - {$resp<reason> // ''}" unless $resp<success>;
    my $body = self!decode-response($resp);

    my $feed;
    my $parse-err;
    try { $feed = parse-feed($body) };
    $parse-err = $!;
    return $feed if $feed.defined;
    note "Feed parse failed at {$url}, falling back to HTML discovery: $parse-err" if $parse-err;

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
    for $tag.match(/:i ( <[\w:-]>+ ) \s* [ '=' \s* ( \" <-["]>* \" || \' <-[']>* \' || \S+ ) ]? /, :global) -> $m {
        my $name = ~$m[0];
        if $m[1].defined {
            my $raw = ~$m[1];
            my $val = $raw;
            if $raw.starts-with('"') && $raw.ends-with('"') {
                $val = $raw.substr(1, $raw.chars - 2);
            } elsif $raw.starts-with("'") && $raw.ends-with("'") {
                $val = $raw.substr(1, $raw.chars - 2);
            }
            %attrs{$name.lc} = decode-entities($val);
        } else {
            %attrs{$name.lc} = True;
        }
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
    return $url if $url.lc.starts-with('http://') || $url.lc.starts-with('https://');
    my $scheme = try { URI.new($base).scheme.lc } // 'https';
    return $scheme ~ ':' ~ $url if $url ~~ /^\/\//;

    my $b = try { URI.new($base) } // return $url;
    my $u = try { URI.new($url) }  // return $url;
    my $rp = ~$u.path;
    unless $rp.starts-with('/') {
        my $bp = ~$b.path;
        $bp ~~ s/ <-[/]>* $ // unless $bp.ends-with('/');
        $rp = ($bp.chars ?? $bp !! '/') ~ $rp;
    }
    my $result = $b.clone;
    $result.path($rp);
    $result.query($u.query // "");
    $result.fragment($u.fragment // "");
    ~$result
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
