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

has $.ua is built(False);
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
        self!check-size($resp);
        return $resp;
    }
}

method !check-size($resp) {
    my $cl = header-value($resp<headers><content-length>);
    if $cl.defined && $cl.chars {
        my $len = try +$cl;
        die "Response too large ({$len} bytes, max {MAX-FEED-SIZE})"
            if $len.defined && $len > MAX-FEED-SIZE;
    }
    my $content = $resp<content> // "";
    die "Response too large ({$content.bytes} bytes, max {MAX-FEED-SIZE})"
        if $content.bytes > MAX-FEED-SIZE;
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
    my $body = try { $resp<content>.decode($charset) };
    without $body {
        die "Cannot decode response body using charset '$charset': $!";
    }
    $body
}

# Expand an IPv4 literal into its four octets. Accepts the standard
# dotted-quad form plus the abbreviated dotted forms (127.1, 127.0.1),
# hex forms (0x7f.1), and the 32-bit integer form (2130706433) that
# browsers and inet_aton resolve. Returns an empty list when $host is
# not an IPv4 literal. Dies on octal notation, which is ambiguous and
# rejected outright.
method !ipv4-octets(Str $host --> List) {
    my @parts = $host.split('.');
    return () unless 1 <= @parts.elems <= 4;
    my @vals;
    for @parts {
        my $v;
        if $_ ~~ /^ '0x' <[0..9a..fA..F]>+ $/ {
            $v = :16($_.substr(2));
        } elsif $_ ~~ /^ \d+ $/ {
            $v = +$_;
        } else {
            return ();
        }
        return () unless $v.defined;
        @vals.push: $v;
    }
    # Octal notation is ambiguous and rejected outright, but only when every
    # label is a genuine numeric/hex IPv4 component. A hostname like
    # '01.example.com' has non-numeric labels and is not an IP literal.
    die "Blocked IPv4 address with octal notation"
        if @parts.first({ .chars > 1 && .starts-with('0') && !.starts-with('0x') && !.starts-with('0X') });
    # inet_aton-style expansion: the first n-1 values are single octets;
    # the last value spans the remaining 5-n octets, big-endian.
    my @octets = 0 xx 4;
    my $last = @vals.pop;
    my $rest = @vals.elems;
    for @vals.kv -> $i, $v {
        return () unless $v <= 0xFF;
        @octets[$i] = $v;
    }
    my $span = 4 - $rest;
    return () unless $last <= (1 +< (8 * $span)) - 1;
    for ^$span -> $k {
        @octets[$rest + $k] = ($last +> (8 * ($span - 1 - $k))) +& 0xFF;
    }
    @octets
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
    $host .= subst(/ ^ '[' /, '');
    $host .= subst(/ ']' $ /, '');
    # Strip trailing dot (DNS absolute form) so bare-hostname check catches internal.
    $host .= subst(/ '.' $ /, '');
    # Reject bare hostnames (no dots) — SSRF via internal DNS short names
    die "Blocked host without domain" unless $host.contains('.') || $host.contains(':');
    # Reject private, loopback, and link-local IPv4 addresses,
    # including short forms (127.1, 127.0.1, 0x7f.1) and the
    # 32-bit integer form (2130706433).
    my @ipv4 = self!ipv4-octets($host);
    if @ipv4 {
        my ($a, $b, $c, $d) = @ipv4;
        die "Blocked unspecified address" if $a == 0 && $b == 0 && $c == 0 && $d == 0;
        die "Blocked address on zero network" if $a == 0;
        die "Blocked loopback address"    if $a == 127;
        die "Blocked link-local address"  if $a == 169 && $b == 254;
        die "Blocked private address"     if $a == 10;
        die "Blocked private address"     if $a == 192 && $b == 168;
        die "Blocked private address"     if $a == 172 && 16 <= $b <= 31;
    }
    # Check IPv4-mapped IPv6 (::ffff:x.x.x.x, ::ffff:127.1, or ::ffff:hex:hex)
    if $host ~~ /^ '::ffff:' (.+) $/ {
        my $suffix = ~$0;
        my @octets = self!ipv4-octets($suffix);
        if @octets {
            my ($a, $b, $c, $d) = @octets;
            die "Blocked mapped unspecified address" if $a == 0 && $b == 0 && $c == 0 && $d == 0;
            die "Blocked mapped loopback"      if $a == 127;
            die "Blocked mapped link-local"   if $a == 169 && $b == 254;
            die "Blocked mapped private"      if $a == 10 || $a == 192 && $b == 168
                                                  || $a == 172 && 16 <= $b <= 31;
        } else {
            my $hex-str = $suffix.split(':').map({ .chars == 4 ?? $_ !! (try sprintf('%04x', :16($_)) // die "Invalid hex segment in IPv4-mapped IPv6: $_") }).join;
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
    # Check IPv4-compatible/embedded IPv6 (::127.0.0.1, 0:0:0:0:0:0:127.0.0.1).
    # The dotted-quad is anchored to the end of the address so the full quad
    # is captured; a greedy hex prefix would otherwise swallow leading octets
    # and let ::127.0.0.1 slip through as 7.0.0.1.
    if $host.contains(':') && $host ~~ / (\d+) '.' (\d+) '.' (\d+) '.' (\d+) $ / {
        my @octets = (~$0, ~$1, ~$2, ~$3);
        die "Blocked IPv6 with octal notation" if @octets.first({ .chars > 1 && .starts-with('0') });
        my ($a, $b, $c, $d) = (+$0, +$1, +$2, +$3);
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
        die "Blocked IPv6 unspecified address"   if $addr eq '::';
        die "Blocked IPv6 link-local address"   if $addr ~~ /^ fe <[89a..b]> /;
        die "Blocked IPv6 unique-local address" if $addr.starts-with('fc') || $addr.starts-with('fd');
        # Reject IPv6 translation prefixes that embed a private IPv4:
        # 6to4 (2002::/16), Teredo (2001:0000::/32, server field), NAT64
        # (64:ff9b::/96), and IPv4-compatible/translated (::x.x.x.x in hex).
        my @embedded = self!ipv4-from-translation-prefix($addr);
        if @embedded {
            my ($a, $b, $c, $d) = @embedded;
            die "Blocked embedded unspecified address" if $a == 0 && $b == 0 && $c == 0 && $d == 0;
            die "Blocked embedded loopback address"    if $a == 127;
            die "Blocked embedded link-local address"  if $a == 169 && $b == 254;
            die "Blocked embedded private address"     if $a == 10 || $a == 192 && $b == 168
                                                            || $a == 172 && 16 <= $b <= 31;
        }
    }
}

# Extract the IPv4 address embedded in an IPv6 translation prefix.
# Returns the four octets, or an empty list when $addr is not a pure-hex
# IPv6 address in one of the handled prefixes.
method !ipv4-from-translation-prefix(Str $addr --> List) {
    my @both = $addr.split('::');
    return () if @both.elems > 2;
    my @h = @both[0].chars ?? @both[0].split(':') !! [];
    my @tail = @both[1].defined && @both[1].chars ?? @both[1].split(':') !! [];
    if @both.elems == 1 {
        return () unless @h.elems == 8;
    } else {
        return () if @h.elems + @tail.elems > 7;
        @h.append: ('0' xx (8 - @h.elems - @tail.elems));
        @h.append: @tail;
    }
    my @val;
    for @h -> $hextet {
        return () unless $hextet ~~ /^<[0..9a..fA..F]>+$/;
        @val.push: :16($hextet);
    }
    return () unless @val.elems == 8;
    my sub pair-octets($n) { [($n +> 8) +& 0xFF, $n +& 0xFF] }
    my @octets;
    if @val[0] == 0x2002 {
        # 6to4: IPv4 occupies bits 16-47 (hextets 2-3)
        @octets = (|pair-octets(@val[1]), |pair-octets(@val[2]));
    } elsif @val[0] == 0x2001 && @val[1] == 0 {
        # Teredo 2001:0000::/32: server IPv4 occupies bits 32-63 (hextets 3-4)
        @octets = (|pair-octets(@val[2]), |pair-octets(@val[3]));
    } elsif @val[0] == 0x64 && @val[1] == 0xff9b
        && @val[2] == 0 && @val[3] == 0 && @val[4] == 0 && @val[5] == 0 {
        # NAT64 well-known 64:ff9b::/96: IPv4 occupies the last 32 bits
        @octets = (|pair-octets(@val[6]), |pair-octets(@val[7]));
    } elsif @val[0] == 0 && @val[1] == 0 && @val[2] == 0 && @val[3] == 0
        && @val[4] == 0 && @val[5] == 0 {
        # IPv4-compatible/translated: hex form of ::x.x.x.x (last 32 bits)
        @octets = (|pair-octets(@val[6]), |pair-octets(@val[7]));
    }
    @octets
}

method fetch(Str $url --> Syndicate::Feed:D) {
    my $resp = self!fetch-url($url);
    die "HTTP {$resp<status>} - {$resp<reason> // ''}" unless $resp<success>;
    my $ct = header-value($resp<headers><content-type>) // '';
    die "Unexpected Content-Type: '$ct' — expected application/atom+xml, application/rss+xml, application/feed+json, application/json, or text/xml"
        unless !$ct.trim.chars
            || $ct.lc ~~ /^ :i [ 'application/' [ atom\+xml | rss\+xml | feed\+json | xml | json ] | 'text/xml' ] [ \s* ';' <-[;]>* ]* $/;
    my $body = self!decode-response($resp);
    parse-feed($body)
}

method discover(Str $url --> Syndicate::Feed:D) {
    my $resp = self!fetch-url($url);
    die "HTTP {$resp<status>} - {$resp<reason> // ''}" unless $resp<success>;
    my $body = self!decode-response($resp);

    # Parse in a single XML/JSON pass and non-recordingly: HTML pages are a
    # normal case for discover(), so a non-feed body is not an error.
    with parse-feed-or-nil($body) -> $feed {
        return $feed;
    }

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
    my $clean = $html.subst(:g,
        / '<!--' .*? '-->'
        | '<script' [<-[>]>]* '>' .*? '</script>'
        | '<style'  [<-[>]>]* '>' .*? '</style>' /,
        :i);

    for $clean.comb($link-tag) -> $tag {
        my %attr = self!parse-attrs($tag);
        my $rel = (%attr<rel> // '').lc;
        next unless $rel.split(/\s+/, :skip-empty).any eq 'alternate';
        my $tv = (%attr<type> // "").lc;
        next unless $tv eq 'application/rss+xml'
                  || $tv eq 'application/atom+xml'
                  || $tv eq 'application/feed+json';
        next unless %attr<href> ~~ Str && %attr<href>.chars;
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
        # A valueless <base href> parses to a Bool True; never return it as
        # the base URL (guard with a type check to avoid an X::TypeCheck).
        return %attr<href> if %attr<href> ~~ Str;
    }
    Str
}

sub normalize-path(Str $path --> Str) {
    my $leading = $path.starts-with('/');
    my $trailing = $path.ends-with('/');
    my @parts;
    for $path.split('/') {
        when ''  { next }  # skip empty strings from leading/trailing/double slashes
        when '.' { next }
        when '..' { @parts.pop if @parts }
        default  { @parts.push($_) }
    }
    my $result = @parts.join('/');
    $leading = $leading && ?@parts;
    $result = $leading ?? '/' ~ $result !! $result;
    return '/' if $trailing && !$leading && !@parts;
    $result ~ ($trailing ?? '/' !! '')
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
        # Per RFC 3986 §5.4, only merge with the base directory when the
        # reference has a path; a query/fragment-only reference keeps the
        # base path intact (including its last segment).
        $bp ~~ s/ <-[/]>* $ // unless $bp.ends-with('/') || !$rp.chars;
        $rp = ($bp.chars ?? $bp !! '/') ~ $rp;
    }
    $rp = normalize-path($rp);
    my $result = $b.clone;
    $result.path($rp);
    # Per RFC 3986 §5.4, a reference without a query component (fragment-only
    # or empty reference) keeps the base query, so only overwrite it when the
    # reference actually carries a path (test the RAW reference path, not the
    # merged one) or an explicit '?'.
    if ~$u.path || $url.split('#')[0].contains('?') {
        $result.query($u.query // "");
    }
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
requiring TLS verification, pass a custom C<:$ua>. The custom user agent must
duck-type C<HTTP::Tiny>: respond to C<.get(Str $url)> with a C<Hash> whose
C<success>, C<status>, C<reason>, C<content>, and C<headers> keys behave like
C<HTTP::Tiny>'s response (C<content-type>, C<content-length>, C<location>
headers). Note that C<Cro::HTTP::Client> and C<HTTP::UserAgent> do B<not>
satisfy this contract as-is.

Responses are limited to C<MAX-FEED-SIZE> bytes (10 MiB). The C<Content-Length>
header is checked before the body is accepted, and the buffered body is
re-checked afterwards; a server that streams a body without a
C<Content-Length> header is therefore still fully buffered before the limit
is enforced.

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
