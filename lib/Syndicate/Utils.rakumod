use v6.d;
use XML;
use XML::Entity;
use DateTime::Grammar;
use DateTime::Format::RFC2822;
use Syndicate::Stats;

my constant NS-ATOM is export = 'http://www.w3.org/2005/Atom';
my constant %TZ-OFFSET = (
    'EST'  => '-0500', 'EDT'  => '-0400',
    'CST'  => '-0600', 'CDT'  => '-0500',
    'MST'  => '-0700', 'MDT'  => '-0600',
    'PST'  => '-0800', 'PDT'  => '-0700',
    'CET'  => '+0100', 'CEST' => '+0200',
    'EET'  => '+0200', 'EEST' => '+0300',
    'IST'  => '+0530', 'HKT'  => '+0800',
    'JST'  => '+0900', 'AEST' => '+1000',
    'AEDT' => '+1100', 'NZST' => '+1200',
    'NZDT' => '+1300',
);

# Full HTML 4.01 named character reference set (case-sensitive), plus the
# apostrophe and uppercase spellings of the XML predefined entities so that
# e.g. &Aacute; and &amp; / &AMP; all decode as expected.
my constant %HTML-ENTITIES is export = (
    'AElig' => 198, 'Aacute' => 193, 'Acirc' => 194, 'Agrave' => 192,
    'Alpha' => 913, 'Aring' => 197, 'Atilde' => 195, 'Auml' => 196,
    'Beta' => 914, 'Ccedil' => 199, 'Chi' => 935, 'Dagger' => 8225,
    'Delta' => 916, 'ETH' => 208, 'Eacute' => 201, 'Ecirc' => 202,
    'Egrave' => 200, 'Epsilon' => 917, 'Eta' => 919, 'Euml' => 203,
    'Gamma' => 915, 'Iacute' => 205, 'Icirc' => 206, 'Igrave' => 204,
    'Iota' => 921, 'Iuml' => 207, 'Kappa' => 922, 'Lambda' => 923,
    'Mu' => 924, 'Ntilde' => 209, 'Nu' => 925, 'OElig' => 338,
    'Oacute' => 211, 'Ocirc' => 212, 'Ograve' => 210, 'Omega' => 937,
    'Omicron' => 927, 'Oslash' => 216, 'Otilde' => 213, 'Ouml' => 214,
    'Phi' => 934, 'Pi' => 928, 'Prime' => 8243, 'Psi' => 936,
    'Rho' => 929, 'Scaron' => 352, 'Sigma' => 931, 'THORN' => 222,
    'Tau' => 932, 'Theta' => 920, 'Uacute' => 218, 'Ucirc' => 219,
    'Ugrave' => 217, 'Upsilon' => 933, 'Uuml' => 220, 'Xi' => 926,
    'Yacute' => 221, 'Yuml' => 376, 'Zeta' => 918, 'aacute' => 225,
    'acirc' => 226, 'acute' => 180, 'aelig' => 230, 'agrave' => 224,
    'alefsym' => 8501, 'alpha' => 945, 'amp' => 38, 'and' => 8743,
    'ang' => 8736, 'aring' => 229, 'asymp' => 8776, 'atilde' => 227,
    'auml' => 228, 'bdquo' => 8222, 'beta' => 946, 'brvbar' => 166,
    'bull' => 8226, 'cap' => 8745, 'ccedil' => 231, 'cedil' => 184,
    'cent' => 162, 'chi' => 967, 'circ' => 710, 'clubs' => 9827,
    'cong' => 8773, 'copy' => 169, 'crarr' => 8629, 'cup' => 8746,
    'curren' => 164, 'dArr' => 8659, 'dagger' => 8224, 'darr' => 8595,
    'deg' => 176, 'delta' => 948, 'diams' => 9830, 'divide' => 247,
    'eacute' => 233, 'ecirc' => 234, 'egrave' => 232, 'empty' => 8709,
    'emsp' => 8195, 'ensp' => 8194, 'epsilon' => 949, 'equiv' => 8801,
    'eta' => 951, 'eth' => 240, 'euml' => 235, 'euro' => 8364,
    'exist' => 8707, 'fnof' => 402, 'forall' => 8704, 'frac12' => 189,
    'frac14' => 188, 'frac34' => 190, 'frasl' => 8260, 'gamma' => 947,
    'ge' => 8805, 'gt' => 62, 'hArr' => 8660, 'harr' => 8596,
    'hearts' => 9829, 'hellip' => 8230, 'iacute' => 237, 'icirc' => 238,
    'iexcl' => 161, 'igrave' => 236, 'image' => 8465, 'infin' => 8734,
    'int' => 8747, 'iota' => 953, 'iquest' => 191, 'isin' => 8712,
    'iuml' => 239, 'kappa' => 954, 'lArr' => 8656, 'lambda' => 955,
    'lang' => 9001, 'laquo' => 171, 'larr' => 8592, 'lceil' => 8968,
    'ldquo' => 8220, 'le' => 8804, 'lfloor' => 8970, 'lowast' => 8727,
    'loz' => 9674, 'lrm' => 8206, 'lsaquo' => 8249, 'lsquo' => 8216,
    'lt' => 60, 'macr' => 175, 'mdash' => 8212, 'micro' => 181,
    'middot' => 183, 'minus' => 8722, 'mu' => 956, 'nabla' => 8711,
    'nbsp' => 160, 'ndash' => 8211, 'ne' => 8800, 'ni' => 8715,
    'not' => 172, 'notin' => 8713, 'nsub' => 8836, 'ntilde' => 241,
    'nu' => 957, 'oacute' => 243, 'ocirc' => 244, 'oelig' => 339,
    'ograve' => 242, 'oline' => 8254, 'omega' => 969, 'omicron' => 959,
    'oplus' => 8853, 'or' => 8744, 'ordf' => 170, 'ordm' => 186,
    'oslash' => 248, 'otilde' => 245, 'otimes' => 8855, 'ouml' => 246,
    'para' => 182, 'part' => 8706, 'permil' => 8240, 'perp' => 8869,
    'phi' => 966, 'pi' => 960, 'piv' => 982, 'plusmn' => 177,
    'pound' => 163, 'prime' => 8242, 'prod' => 8719, 'prop' => 8733,
    'psi' => 968, 'quot' => 34, 'rArr' => 8658, 'radic' => 8730,
    'rang' => 9002, 'raquo' => 187, 'rarr' => 8594, 'rceil' => 8969,
    'rdquo' => 8221, 'real' => 8476, 'reg' => 174, 'rfloor' => 8971,
    'rho' => 961, 'rlm' => 8207, 'rsaquo' => 8250, 'rsquo' => 8217,
    'sbquo' => 8218, 'scaron' => 353, 'sdot' => 8901, 'sect' => 167,
    'shy' => 173, 'sigma' => 963, 'sigmaf' => 962, 'sim' => 8764,
    'spades' => 9824, 'sub' => 8834, 'sube' => 8838, 'sum' => 8721,
    'sup' => 8835, 'sup1' => 185, 'sup2' => 178, 'sup3' => 179,
    'supe' => 8839, 'szlig' => 223, 'tau' => 964, 'there4' => 8756,
    'theta' => 952, 'thetasym' => 977, 'thinsp' => 8201, 'thorn' => 254,
    'tilde' => 732, 'times' => 215, 'trade' => 8482, 'uArr' => 8657,
    'uacute' => 250, 'uarr' => 8593, 'ucirc' => 251, 'ugrave' => 249,
    'uml' => 168, 'upsih' => 978, 'upsilon' => 965, 'uuml' => 252,
    'weierp' => 8472, 'xi' => 958, 'yacute' => 253, 'yen' => 165,
    'yuml' => 255, 'zeta' => 950, 'zwj' => 8205, 'zwnj' => 8204,
    'apos' => 39, 'AMP' => 38, 'LT' => 60, 'GT' => 62, 'QUOT' => 34, 'APOS' => 39,
);

unit module Syndicate::Utils:ver<0.0.1>:auth<zef:sasha>;

my constant $XML-ENTITY = XML::Entity.new;
my constant RFC2822-FORMAT is export = DateTime::Format::RFC2822.new;

sub decode-entities(Str $text --> Str) is export {
    return $text unless $text.defined && $text.chars;
    # Single-pass decoder: numeric character references (&#NN; / &#xHH;),
    # the five predefined XML entities, and the HTML 4.01 named character
    # references. Unknown named entities are left as literal text, and the
    # replacement is never rescanned, so a raw '&amp;#8217;' decodes to
    # '&#8217;' rather than to an apostrophe.
    $text.subst(:g,
        / '&' [ $<hex>   = ( '#x' <[0..9a..fA..F]>+ ';' )
               | $<dec>  = ( '#' \d+ ';' )
               | $<named> = ( <[a..zA..Z]>+ ';' ) ] /,
        {
            with $<hex> { try { chr(:16(~$<hex>.substr(2, *-1))) } // ~$/ }
            orwith $<dec> { try { chr(+~$<dec>.substr(1, *-1)) } // ~$/ }
            else {
                # Named references: the XML predefined entities plus the
                # HTML 4.01 set, matched case-sensitively.
                my $name = ~$<named>.substr(0, *-1);
                with %HTML-ENTITIES{$name} -> $cp {
                    try { chr($cp) } // ~$/
                } else {
                    ~$/
                }
            }
        });
}

sub encode-entities(Str $text --> Str) is export {
    return $text unless $text.defined && $text.chars;
    $XML-ENTITY.encode($text)
}

sub add-element($parent, $name, $value --> Nil) is export {
    return unless $value.defined;
    $parent.append: XML::Element.new(:name($name), :nodes([encode-entities($value)]));
}

sub add-attrib($elem, $name, $value --> Nil) is export {
    return unless $value.defined;
    $elem.attribs{$name} = encode-entities($value);
}

# Runs $fn and records a Stats error when it throws, then rethrows.
# X::Control exceptions (return/next/etc.) pass through untouched so they
# never inflate the error count.
sub with-error-recording(&fn --> Any) is export {
    CATCH {
        when X::Control { .rethrow }
        default { Syndicate::Stats.record-error; .rethrow }
    }
    &fn()
}

sub has-nonempty-text($elem, $tag --> Bool) is export {
    my $e = $elem.elements(:TAG($tag))[0]
        or return False;
    so element-text($e).trim.chars
}

proto sub node-text($node --> Str) is export {*}
multi sub node-text(XML::Text $n)    { $n.text }
multi sub node-text(XML::CDATA $n)   { $n.data }
multi sub node-text(XML::Element $n) { $n.nodes.map(&node-text).join }
multi sub node-text($n)              { "" }

sub element-text($e --> Str) is export { $e.nodes.map(&node-text).join }

sub get-text($parent, $tag --> Str) is export {
    my $e = $parent.elements(:TAG($tag))[0];
    die "Missing required element <$tag> in <{$parent.name}>" without $e;
    my $text = element-text($e).trim;
    die "Empty required element <$tag> in <{$parent.name}>" unless $text.chars;
    return decode-entities($text);
}

sub text-of-optional($e --> Str) {
    my $text = element-text($e).trim;
    $text.chars ?? decode-entities($text) !! Str
}

sub get-text-optional($parent, $tag --> Str) is export {
    # Note: Returns Str (type object) for both "element missing" and
    # "element empty". Use .defined to distinguish from a found value.
    my $e = $parent.elements(:TAG($tag))[0];
    $e.defined ?? text-of-optional($e) !! Str
}

sub get-text-by-ns($parent, $local-name, $ns-uri --> Str) is export {
    # XML::Element.elements() can only match literal element names, so a
    # namespaced element whose prefix differs from the canonical one (e.g.
    # <content-enc:encoded>) would be missed. Resolve the URI to the prefix
    # actually in scope and match that spelling instead.
    my $prefix = $parent.nsPrefix($ns-uri);
    return Str without $prefix;
    my $tag = $prefix.chars ?? "$prefix:$local-name" !! $local-name;
    my $e = $parent.elements(:TAG($tag))[0];
    $e.defined ?? text-of-optional($e) !! Str
}

sub parse-categories($parent --> Array) is export {
    my @categories;
    for $parent.elements(:TAG<category>) -> $c {
        my $text = element-text($c).trim;
        @categories.push: decode-entities($text) if $text.chars;
    }
    @categories
}

sub normalize-date-str(Str $str --> Str) {
    my $s = $str;
    $s .= subst(/ (\d ** 1..2) ':' (\d ** 2) ':' (\d ** 2) \s* (:i <[PA]>M) /, -> $/ {
        my $h = +$0;
        if ~$3.lc eq 'am' { $h = 0 if $h == 12 }
        else              { $h += 12 if $h < 12 }
        sprintf "%02d:%02d:%02d", $h, +$1, +$2;
    });
    $s .= subst(/ (\d ** 1..2) ':' (\d ** 2) \s* (:i <[PA]>M) /, -> $/ {
        my $h = +$0;
        if ~$2.lc eq 'am' { $h = 0 if $h == 12 }
        else              { $h += 12 if $h < 12 }
        sprintf "%02d:%02d:%02d", $h, +$1, 0;
    });
    $s .= subst(:g, /
        << EST >> | << EDT >> | << CST >> | << CDT >> |
        << MST >> | << MDT >> | << PST >> | << PDT >> |
        << CET >> | << CEST >> | << EET >> | << EEST >> |
        << IST >> | << HKT >> | << JST >> |
        << AEST >> | << AEDT >> | << NZST >> | << NZDT >>
    /, {
        %TZ-OFFSET{~$/}
    });
    # Space-separated ISO datetimes (e.g. '2024-01-15 08:30:00 -0500') are
    # rejected by datetime-interpret; convert them to the T-separated form.
    # The date prefix requires an ISO YYYY-MM-DD shape, so RFC 2822 dates
    # (month names) are never affected.
    $s .= subst(:g, /
        (\d ** 4 '-' \d ** 2 '-' \d ** 2) ' ' (\d ** 2 ':' \d ** 2 ':' \d ** 2)
        ' '? (<[+-]> \d ** 2 ':'? \d ** 2)? $ /
    , { "$0T$1" ~ ($2 // '') });
    # Datetimes without any timezone designator are treated as UTC rather
    # than silently dropped. Only clock times qualify, so bare dates like
    # '2024-01-15' (which datetime-interpret already handles) are untouched.
    $s ~= 'Z' if $s ~~ / \d ** 2 ':' \d ** 2 \s* $ /
        && $s !~~ / ( 'Z' | <[+-]> \d ** 2 ':'? \d ** 2 ) \s* $ /;
    $s
}

sub parse-date(Str $str --> DateTime) is export {
    die "parse-date: empty or unset string" unless $str.defined && $str.trim.chars > 0;
    my $normalized = normalize-date-str($str.trim);
    my $dt = datetime-interpret($normalized) // die "parse-date: cannot parse '$str'";
    apply-source-offset($dt, $normalized)
}

sub parse-date-optional(Any $str) is export {
    return Nil unless $str.defined && $str.Str.trim.chars > 0;
    my $normalized = normalize-date-str($str.Str.trim);
    with datetime-interpret($normalized) -> $dt {
        apply-source-offset($dt, $normalized)
    }
}

# DateTime::Actions::Raku mis-handles numeric offsets: ISO +HH:MM/+HHMM
# offsets are dropped (treated as UTC) and RFC 2822 four-digit offsets with
# non-zero minutes are mangled via a ×36 bodge (e.g. +0530 → +05:18). Whole
# hours (-0500) only work by coincidence. Extract the authoritative offset
# from the source and rebuild the DateTime when the parsed offset differs.
sub apply-source-offset(DateTime $dt, Str $normalized --> DateTime) {
    if $normalized ~~ / \s* (<[+-]>) (\d ** 2) \s* ':'? \s* (\d ** 2) \s* $ / {
        my $sign    = ~$0 eq '-' ?? -1 !! 1;
        my $correct = $sign * (+$1 * 3600 + +$2 * 60);
        return $dt if $dt.timezone == $correct;
        return DateTime.new($dt.utc + ($dt.timezone - $correct), :timezone($correct));
    }
    $dt
}

sub compute-needs(@items --> Hash) is export {
    my Bool ($needs-dc, $needs-media, $needs-itunes, $needs-content) = False xx 4;
    for @items -> $item {
        my %nf = $item.?namespace-flags // %();
        $needs-dc      ||= ?%nf<dc>;
        $needs-media   ||= ?%nf<media>;
        $needs-itunes  ||= ?%nf<itunes>;
        $needs-content ||= ?%nf<content>;
    }
    %(:dc($needs-dc), :media($needs-media), :itunes($needs-itunes), :content($needs-content))
}

=begin pod

=head1 NAME

Syndicate::Utils - Internal utility functions

=head1 DESCRIPTION

Shared helper functions used by parser/generator classes.
Not typically needed by end users.

=head1 EXPORTED SUBS

=item C<decode-entities(Str)>, C<encode-entities(Str)> - XML entity handling
=item C<get-text($parent, $tag)> - Get required text content, dies if element missing
=item C<get-text-optional($parent, $tag)> - Get optional text content (returns C<Str>)
=item C<parse-categories($parent)> - Extract category tags text content
=item C<with-error-recording(&fn)> - Run block, recording a Stats error on throw
=item C<has-nonempty-text($elem, $tag)> - Whether element has non-empty text content
=item C<parse-date(Str)> - Parse date string, dies on bad input, returns C<DateTime>
=item C<parse-date-optional(Str)> - Parse date string returning C<DateTime> or C<Nil>

=end pod
