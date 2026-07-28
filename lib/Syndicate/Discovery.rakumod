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
has Int $!max-redirect = 5;

=begin comment
TLS: HTTP::Tiny (v0.2.7) and IO::Socket::SSL do not support certificate
verification. Pass a custom :$ua (e.g. Cro::HTTP::Client) for verified
TLS connections.
=end comment
submethod BUILD(Int :$max-redirect = 5, :$ua) {
    with $ua { $!ua = $_ }
    $!ua //= HTTP::Tiny.new(:max-redirect(0));
    $!max-redirect = $max-redirect;
}

method !resolve-redirect-url(Str $original, Str $location) {
    return $location if $location.lc.starts-with('http://') || $location.lc.starts-with('https://');
    self.resolve-url($location, $original)
}

method !fetch-url(Str $url is copy) {
    my $max = $!max-redirect;
    loop {
        self!validate-url($url);
        my $resp = $.ua.get($url);
        if my $location = $resp<headers><location> {
            my $loc = $location ~~ Array ?? $location[0] !! $location;
            die "Too many redirects" if --$max < 0;
            $url = self!resolve-redirect-url($url, $loc);
            next;
        }
        return $resp;
    }
}

sub header-value($h) {
    $h ~~ Array ?? $h[0] // '' !! $h // ''
}

method !decode-response($resp --> Str) {
    my $charset = 'utf-8';
    with $resp<headers><content-type> {
        my $ct = header-value($_);
        for $ct.lc.split(';') {
            .trim ~~ /^charset\s* \= \s* (<[^\s;]>+)/ and $charset = ~$0.subst(/<[\'\"]>/, '', :g);
        }
    }
    $resp<content>.decode($charset)
}

method !validate-url(Str $url) {
    my $uri = try { URI.new($url) };
    die "Invalid URL" without $uri;
    my $scheme = $uri.scheme.lc;
    die "Blocked URL scheme — only http and https are permitted"
        unless $scheme.defined && $scheme ∈ <http https>;
    my $host = $uri.host.lc;
    die "Blocked empty host" unless $host.defined && $host.chars;
    # Strip brackets so all subsequent checks work with bare addresses
    $host .= subst(/ ^ '[' | ']' $ /, '');
    # Reject bare hostnames (no dots) — SSRF via internal DNS short names
    die "Blocked host without domain" unless $host.contains('.');
    # Reject private, loopback, and link-local IPv4 addresses
    if $host ~~ /^ (\d+) '.' (\d+) '.' (\d+) '.' (\d+) $/ {
        my @octets = (~$0, ~$1, ~$2, ~$3);
        die "Blocked IPv4 address with octal notation" if @octets.first({ .chars > 1 && .starts-with('0') });
        my ($a, $b, $c, $d) = (+$0, +$1, +$2, +$3);
        die "Blocked unspecified address" if $a == 0 && $b == 0 && $c == 0 && $d == 0;
        die "Blocked loopback address"    if $a == 127;
        die "Blocked link-local address"  if $a == 169 && $b == 254;
        die "Blocked private address"     if $a == 10;
        die "Blocked private address"     if $a == 192 && $b == 168;
        die "Blocked private address"     if $a == 172 && 16 <= $b <= 31;
    }
    # Check IPv4-mapped IPv6 (::ffff:x.x.x.x or ::ffff:hex:hex)
    if $host ~~ /^ '::ffff:' (.+) $/ {
        my $suffix = ~$0;
        if $suffix ~~ /^ (\d+) '.' (\d+) '.' (\d+) '.' (\d+) $/ {
            my ($a, $b, $c, $d) = (+$0, +$1, +$2, +$3);
            die "Blocked mapped unspecified address" if $a == 0 && $b == 0 && $c == 0 && $d == 0;
            die "Blocked mapped loopback"      if $a == 127;
            die "Blocked mapped link-local"   if $a == 169 && $b == 254;
            die "Blocked mapped private"      if $a == 10 || $a == 192 && $b == 168
                                                  || $a == 172 && 16 <= $b <= 31;
        } else {
            my $hex-str = $suffix.split(':').map({ .chars == 4 ?? $_ !! sprintf('%04s', $_) }).join;
            die "Blocked mapped unspecified address" unless $hex-str.chars == 8 && $hex-str ~~ /^<[0..9a..f]>+$/;
            my $ip = :16($hex-str);
            my $a = ($ip +> 24) +& 0xFF;
            my $b = ($ip +> 16) +& 0xFF;
            my $c = ($ip +> 8) +& 0xFF;
            my $d = $ip +& 0xFF;
            die "Blocked mapped unspecified address" if $a == 0 && $b == 0 && $c == 0 && $d == 0;
            die "Blocked mapped loopback"      if $a == 127;
            die "Blocked mapped link-local"   if $a == 169 && $b == 254;
            die "Blocked mapped private"      if $a == 10 || $a == 192 && $b == 168
                                                  || $a == 172 && 16 <= $b <= 31;
        }
    }
    # Check IPv4-compatible IPv6 (::127.0.0.1, 0:0:0:0:0:0:127.0.0.1)
    if $host ~~ /^ (<[0..9a..f:]>+) (\d+) '.' (\d+) '.' (\d+) '.' (\d+) $/ {
        my @octets = (~$1, ~$2, ~$3, ~$4);
        die "Blocked IPv6 with octal notation" if @octets.first({ .chars > 1 && .starts-with('0') });
        my ($a, $b, $c, $d) = (+$1, +$2, +$3, +$4);
        die "Blocked mapped unspecified address" if $a == 0 && $b == 0 && $c == 0 && $d == 0;
        die "Blocked mapped loopback"      if $a == 127;
        die "Blocked mapped link-local"   if $a == 169 && $b == 254;
        die "Blocked mapped private"      if $a == 10 || $a == 192 && $b == 168
                                              || $a == 172 && 16 <= $b <= 31;
    }
    # Reject zone IDs (e.g. fe80::1%eth0) before the pure-IPv6 regex
    die "Blocked IPv6 address with zone ID" if $host.contains('%');
    # Reject IPv6 loopback, link-local, and ULA
    if $host ~~ /^ (<[0..9a..f:]>+) $/ {
        my $addr = ~$0;
        die "Blocked IPv6 loopback address"     if $addr eq '::1';
        die "Blocked IPv6 link-local address"   if $addr ~~ /^ fe <[89a..b]> /;
        die "Blocked IPv6 unique-local address" if $addr.starts-with('fc') || $addr.starts-with('fd');
    }
}

method fetch(Str $url --> Syndicate::Feed:D) {
    my $resp = self!fetch-url($url);
    die "HTTP {$resp<status>} - {$resp<reason> // ''}" unless $resp<success>;
    my $ct = header-value($resp<headers><content-type>);
    die "Unexpected Content-Type: '$ct' — expected application/atom+xml, application/rss+xml, application/feed+json, or text/xml"
        unless $ct.lc ~~ /:i 'application/' [ atom+xml | rss+xml | feed+json | xml ] | 'text/xml' /;
    my $body = self!decode-response($resp);
    parse-feed($body)
}

method discover(Str $url --> Syndicate::Feed:D) {
    my $resp = self!fetch-url($url);
    die "HTTP {$resp<status>} - {$resp<reason> // ''}" unless $resp<success>;
    my $body = self!decode-response($resp);

    my $feed = try { parse-feed($body) };
    my $parse-err = $!;
    return $feed if $feed.defined;
    note "Feed parse failed at {$url}, falling back to HTML discovery: $parse-err" if $parse-err;

    my $feed-url = self!find-first-feed($body, $url);
    die "No feeds found at $url" unless $feed-url;
    self.fetch($feed-url)
}

method find-feeds(Str $html, Str $base-url --> Array) {
    my @feeds;
    my $base = self.base-url($html) // $base-url;
    # Strip HTML comments, <script>, and <style> blocks to avoid
    # false-positive link detection inside them.
    # Uses non-greedy .*? to handle nested HTML tags within blocks
    # (e.g., <span> inside <script>), unlike the previous negated-char-class
    # approach which stopped at any '<' character.
    my $clean = $html.chars > MAX-FEED-SIZE
        ?? $html
        !! $html.subst(:g,
            / '<!--' .*? '-->'
            | '<script' [<-[>]>]* '>' .*? '</script>'
            | '<style'  [<-[>]>]* '>' .*? '</style>' /,
            :i);

    for $clean.comb($link-tag) -> $tag {
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

method !find-first-feed(Str $html, Str $base-url) {
    self.find-feeds($html, $base-url)[0]
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

sub normalize-path(Str $path --> Str) {
    my @parts;
    for $path.split('/') {
        when '.' { next }
        when '..' { @parts.pop if @parts }
        default  { @parts.push($_) }
    }
    @parts.join('/')
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
    $rp = normalize-path($rp);
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

=head2 C<fetch(Str $url)>

Fetches a URL and parses the feed. Dies on HTTP errors.

B<Security note:> SSL/TLS certificates are B<not> verified by the default
C<HTTP::Tiny> user agent. Neither HTTP::Tiny nor the underlying
IO::Socket::SSL module support certificate verification. For connections
requiring TLS verification, pass a custom C<:$ua> using L<Cro::HTTP|rakudoc:Cro::HTTP>
or L<HTTP::UserAgent|rakudoc:HTTP::UserAgent> instead.

=head2 C<discover(Str $url)>

Fetches a URL, tries to parse as a feed. If that fails, searches the HTML
for C<E<lt>linkE<gt>> feed tags and fetches the first discovered feed URL.

B<Security note:> DNS rebinding within the validation/request window is
theoretically possible but impractical for single-request feed fetching.
The validation runs immediately before each HTTP request, making the
TOCTOU window very small.

=head2 C<find-feeds(Str $html, Str $base-url --> Array)>

Returns an array of feed URLs found in HTML by scanning C<E<lt>linkE<gt>>
tags with C<rel="alternate"> and appropriate type attributes.

=end pod
