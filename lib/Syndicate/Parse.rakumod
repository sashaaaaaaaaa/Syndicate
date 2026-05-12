use v6.d;
use Syndicate::RSS;
use Syndicate::RSS::V0_91;
use Syndicate::RSS::V1_0;
use Syndicate::Atom;
use Syndicate::JSONFeed;

unit module Syndicate::Parse:ver<0.0.1>:auth<zef:sasha>;

enum FeedFormat is export <Atom RSS2 RSS091 RSS1 JSONFeedFmt>;

sub feed-format(Str $input --> FeedFormat) is export {
    my $clean = $input.trim;
    die "Empty input" unless $clean.chars;

    return JSONFeedFmt if $clean.starts-with('{');

    my $root = root-element($clean);
    die "Unknown feed format: cannot find root element" unless $root.defined;

    given $root<name> {
        when 'feed'   { return Atom }
        when 'rss'    {
            return $root<ver> eq '0.91' ?? RSS091 !! RSS2
        }
        when 'rdf:RDF' { return RSS1 }
        default { die "Unknown feed format: <$_>" }
    }
}

sub parse-feed(Str $input --> Any) is export {
    given feed-format($input) {
        when Atom    { return Syndicate::Atom.new($input) }
        when RSS2    { return Syndicate::RSS.new($input) }
        when RSS091  { return Syndicate::RSS::V0_91.new($input) }
        when RSS1    { return Syndicate::RSS::V1_0.new($input) }
        when JSONFeedFmt { return Syndicate::JSONFeed.new($input) }
    }
}

sub root-element(Str $input) {
    my $s = $input.trim;
    my $pos = 0;

    loop {
        my $start = index($s, '<', $pos);
        return Nil unless $start.defined;

        # Scan past XML comments: find the first '-->' after '<!--'
        if $s.substr($start) ~~ /^ '<!--' [\N\n]+? '-->' / {
            $pos = $start + $/.chars;
            next;
        }

        # Scan past CDATA sections: find the first ']]>' after '<![CDATA['
        if $s.substr($start) ~~ /^ '<![CDATA[' [\N\n]+? ']]>' / {
            $pos = $start + $/.chars;
            next;
        }

        # Skip DOCTYPE declarations — scan for > not inside quotes,
        # since PUBLIC/SYSTEM identifiers may contain >
        if $s.substr($start) ~~ /^ '<!DOCTYPE' / {
            $pos = $start;
            my $in-single = False;
            my $in-double = False;
            while $pos < $s.chars {
                my $c = $s.substr($pos++, 1);
                if $c eq '"' && !$in-single    { $in-double = !$in-double }
                elsif $c eq "'" && !$in-double { $in-single = !$in-single }
                elsif $c eq '>' && !$in-single && !$in-double { last }
            }
            next;
        }

        my $close = index($s, '>', $start);
        return Nil unless $close.defined;

        my $tag = $s.substr($start, $close - $start + 1);
        $pos = $close + 1;

        # Skip XML declaration <?xml ...?>
        next if $tag.starts-with('<?');

        # Skip DOCTYPE <!DOCTYPE ...>
        next if $tag.starts-with('<!');

        # Extract tag name: <name ...> or <name/>
        my $inner = $tag.substr(1, $tag.chars - 2).trim;
        my $name-end = $inner.index(' ') // $inner.index('/') // $inner.index('>') // $inner.chars;
        my $name = $inner.substr(0, $name-end);
        next unless $name.chars;

        my $rest = $inner.substr($name-end);

        my $ver = "";
        if $rest ~~ /version\s*\=\s*\"(\S+?)\"/ { $ver = ~$0 }
        elsif $rest ~~ /version\s*\=\s*\'(\S+?)\'/ { $ver = ~$0 }

        return %(:$name, :$ver, :rest($rest))
    }
}

=begin pod

=head1 NAME

Syndicate::Parse - Feed format detection and parsing dispatcher

=head1 SYNOPSIS

=begin code :lang<raku>
use Syndicate::Parse;

my $format = feed-format($input);       # Detect format
my $feed   = parse-feed($input);        # Parse any format
=end code

=head1 DESCRIPTION

Provides auto-detection of feed format from raw input and dispatching
to the appropriate parser class.

=head1 ENUM C<FeedFormat>

=item C<Atom> - Atom 1.0
=item C<RSS2> - RSS 2.0
=item C<RSS091> - RSS 0.91
=item C<RSS1> - RSS 1.0
=item C<JSONFeedFmt> - JSON Feed

=head1 EXPORTED SUBS

=head2 C<feed-format(Str $input --> FeedFormat)>

Detects feed format by inspecting the raw input:
JSON feeds starting with C<{>, XML feeds by root element name and version attribute.

=head2 C<parse-feed(Str $input)>

Detects format and returns an object of the appropriate class
(C<Syndicate::Atom>, C<Syndicate::RSS>, C<Syndicate::RSS::V0_91>,
C<Syndicate::RSS::V1_0>, or C<Syndicate::JSONFeed>).

=end pod
