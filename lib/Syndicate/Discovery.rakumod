use v6.d;
use HTTP::Tiny;
use Syndicate::Parse;

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

    my token link-tag { '<link' [.|\n]*? ['/>' | '>'] }
    for $html.comb(/<link-tag>/) -> $tag {
        my %attr = self!parse-attrs($tag);
        next unless %attr<rel> && %attr<rel>.lc eq 'alternate';
        my $tv = %attr<type>.lc // "";
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
    my token base-tag { '<base' [.|\n]*? ['/>' | '>'] }
    with $html.comb(/<base-tag>/)[0] -> $tag {
        my %attr = self!parse-attrs($tag);
        return %attr<href> if %attr<href>.defined;
    }
    Str
}

method resolve-url(Str $url, Str $base --> Str) {
    return $url if $url ~~ /^https?\:\/\//;
    return $url if $url ~~ /^\/\//;

    if $url.starts-with('/') {
        my $b = $base ~~ /^ (https?\:\/\/ [<-[\/]>+] ) /;
        return $b[0] ~ $url;
    }

    my $b = $base;
    if $b !~~ /\/$/ {
        $b ~~ s/\/<-[\/]>*$/\//;
    }

    $b ~ $url
}
