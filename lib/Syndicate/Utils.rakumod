use v6.d;
use XML;
use XML::Entity;
use DateTime::Grammar;
use DateTime::Format::RFC2822;
use Syndicate::Stats;

my constant NS-ATOM is export = 'http://www.w3.org/2005/Atom';
my constant %TZ-OFFSET = (
    'UT'   => '+0000',
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

# Three-letter month abbreviations, for synthesizing the weekday of
# weekday-less RFC 2822 dates in normalize-date-str.
my constant %MONTH = (
    'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4,
    'may' => 5, 'jun' => 6, 'jul' => 7, 'aug' => 8,
    'sep' => 9, 'oct' => 10, 'nov' => 11, 'dec' => 12,
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

unit module Syndicate::Utils:ver<0.0.6>:auth<zef:sasha>;

my constant $XML-ENTITY = XML::Entity.new;
my constant RFC2822-FORMAT is export = DateTime::Format::RFC2822.new;

sub decode-entities(Str $text --> Str) is export {
    return $text unless $text.defined && $text.chars;
    # Fast path: no '&' means no entity can be present, so skip the regex
    # subst entirely (this runs on every text field during parsing).
    return $text unless $text.contains('&');
    # Single-pass decoder: numeric character references (&#NN; / &#xHH; /
    # &#XHH;), the five predefined XML entities, and the HTML 4.01 named character
    # references. Unknown named entities are left as literal text, and the
    # replacement is never rescanned, so a raw '&amp;#8217;' decodes to
    # '&#8217;' rather than to an apostrophe. The named reference's
    # semicolon is optional to tolerate lenient feeds ('&amp' == '&'), but
    # the name is consumed greedily so '&ampx' stays literal. Numeric
    # references tolerate the missing semicolon too for the same reason
    # ('&#8217' == '&#8217;'). Surrogate code points (U+D800-U+DFFF) and
    # values past U+10FFFF are left as literal text: chr() accepts them but
    # the result is not valid UTF-8 and crashes at any encode boundary.
    $text.subst(:g,
        / '&' [ $<hex>   = ( '#' <[xX]> <[0..9a..fA..F]>+ ';'? )
               | $<dec>  = ( '#' \d+ ';'? )
               | $<named> = ( <[a..zA..Z0..9]>+ ';'? ) ] /,
        {
            with $<hex> {
                my $digits = ~$<hex>.substr(2);
                $digits = $digits.substr(0, *-1) if $digits.ends-with(';');
                my $cp = :16($digits);
                0xD800 <= $cp <= 0xDFFF ?? ~$/ !! (try { chr($cp) } // ~$/)
            }
            orwith $<dec> {
                my $digits = ~$<dec>.substr(1);
                $digits = $digits.substr(0, *-1) if $digits.ends-with(';');
                my $cp = +$digits;
                0xD800 <= $cp <= 0xDFFF ?? ~$/ !! (try { chr($cp) } // ~$/)
            }
            else {
                # Named references: the XML predefined entities plus the
                # HTML 4.01 set, matched case-sensitively.
                my $name = ~$<named>;
                $name = $name.substr(0, *-1) if $name.ends-with(';');
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

# Recursively clones a value for safe export from to-hash, dropping undefined
# slots (Str type objects standing in for absent optional fields) and empty
# containers, so the returned hash never leaks nulls or shared references to
# the live feed/item structures.
sub sanitize($v) is export {
    my sub keep($x) { $x.defined && !(($x ~~ Hash) && !$x) && !(($x ~~ List) && !$x) }
    given $v {
        when Hash {
            my %c;
            for $v.kv -> $k, $val {
                my $s = $val.defined ?? sanitize($val) !! Any;
                %c{$k} = $s if keep($s);
            }
            %c
        }
        when Array | List {
            $v.map({ $_.defined ?? sanitize($_) !! Any }).grep(&keep).Array
        }
        default { $v }
    }
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

# Extract a <content>/<content:encoded> body, preserving inline markup.
# Returns (Str content, Bool is-markup): when the element has element
# children, their serialized markup (tags included) is kept and is-markup is
# True; a text-only body (entity-encoded markup, CDATA, plain text) returns
# the decoded text with is-markup False. This lets generators emit real
# markup for element-form content while keeping entity-encoded bodies
# byte-stable.
sub content-and-markup(XML::Element $e) is export {
    my @kids = $e.nodes;
    if @kids.grep(XML::Element) {
        # Text/CDATA children are stored entity-encoded by the XML module;
        # decode them so the captured markup is the rendered HTML. Whitespace
        # between elements is dropped (the xhtml branch already joins element
        # children only) so round-trips stay byte-stable.
        (@kids.grep({ !($_ ~~ XML::Text && $_ !~~ /\S/) })
            .map({ $_ ~~ XML::Element ?? ~$_ !! decode-entities(node-text($_)) }).join, True)
    } else {
        my $text = decode-entities(element-text($e));
        ($text.defined && $text.chars ?? $text !! Str, False)
    }
}

# Serialize parsed markup back into child nodes for output; returns an empty
# list when $content is plain text or not well-formed XML (so callers fall
# back to entity-encoded text). Mixed text+element bodies keep both, since
# element markup must not drop adjacent text.
sub markup-nodes(Str $content --> List) is export {
    my $frag = try { XML::Document.new("<wrap>{$content}</wrap>") };
    return () unless $frag;
    my @children = $frag.root.nodes.grep({ !($_ ~~ XML::Text && $_ !~~ /\S/) });
    @children.grep(XML::Element) ?? @children !! ()
}

sub get-text-optional($parent, $tag --> Str) is export {
    # Note: Returns Str (type object) for both "element missing" and
    # "element empty". Use .defined to distinguish from a found value.
    my $e = $parent.elements(:TAG($tag))[0];
    $e.defined ?? text-of-optional($e) !! Str
}

sub matches-ns(XML::Element $e, Str $ns-uri, Str $canonical-prefix --> Bool) is export {
    # Namespace membership resolved in the element's own scope (so xmlns
    # declarations made on the element itself are honored). A prefix bound
    # to $ns-uri matches; an undeclared prefix matches only when it is the
    # canonical one (lenient feeds omit the xmlns declaration); an
    # unprefixed element matches only when the default namespace is $ns-uri.
    my $name = $e.name;
    my $idx = $name.index(':');
    my $prefix = $idx.defined ?? $name.substr(0, $idx) !! '';
    with $e.nsURI($prefix) -> $uri {
        $uri eq $ns-uri
    } else {
        so($prefix.chars && $prefix eq $canonical-prefix)
    }
}

sub get-text-by-ns($parent, $local-name, $ns-uri, Str $canonical-prefix = "" --> Str) is export {
    # XML::Element.elements() can only match literal element names, so a
    # namespaced element whose prefix differs from the canonical one (e.g.
    # <content-enc:encoded>) would be missed. Match children by local name
    # and namespace URI resolved in each child's own scope (which also sees
    # xmlns declarations made on the child element itself). An undeclared
    # canonical prefix is tolerated, mirroring matches-ns/elements-by-local-ns.
    for $parent.elements -> $e {
        my $name = $e.name;
        my $idx  = $name.index(':');
        my $local = $idx.defined ?? $name.substr($idx + 1) !! $name;
        next unless $local eq $local-name;
        my $prefix = $idx.defined ?? $name.substr(0, $idx) !! '';
        with $e.nsURI($prefix) {
            return text-of-optional($e) if $_ eq $ns-uri;
        } else {
            return text-of-optional($e)
                if $prefix.chars && $prefix eq $canonical-prefix;
        }
    }
    Str
}

sub elements-by-local-ns($parent, $ns-uri, $local-name, Str $canonical-prefix --> List) is export {
    # Namespace-aware child lookup that honors bindings declared on the
    # parent/ancestors AND on the child element itself (where nsPrefix on
    # the parent cannot see them). Each child resolves the URI in its own
    # scope and matches when the resolved URI equals $ns-uri; an undeclared
    # canonical prefix is tolerated as a lenient feed.
    my @matched;
    for $parent.elements -> $e {
        my $name = $e.name;
        my $idx  = $name.index(':');
        my $local = $idx.defined ?? $name.substr($idx + 1) !! $name;
        next unless $local eq $local-name;
        @matched.push: $e if matches-ns($e, $ns-uri, $canonical-prefix);
    }
    @matched
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
        << UT >> | << EST >> | << EDT >> | << CST >> | << CDT >> |
        << MST >> | << MDT >> | << PST >> | << PDT >> |
        << CET >> | << CEST >> | << EET >> | << EEST >> |
        << IST >> | << HKT >> | << JST >> |
        << AEST >> | << AEDT >> | << NZST >> | << NZDT >>
    /, {
        %TZ-OFFSET{~$/}
    });
    # RFC 2822 leniency. DateTime::Grammar rejects several real-world RFC 2822
    # shapes: single-digit days/hours, seconds-less clock times, numeric
    # offsets without a leading space or with a colon, and weekday-less dates.
    # Normalize those here. The guard (3-letter month + 4-digit year) proves an
    # RFC 2822 shape, so ISO datetimes are never affected.
    if $s ~~ / <[a..zA..Z]> ** 3 ' ' \d ** 4 / {
        # 1. Pad single-digit days ('Wed, 1 Jan 2020').
        $s .= subst(:g, /
            ( <[a..zA..Z]> ** 3 ','? \s* ) (\d) ' ' ( <[a..zA..Z]> ** 3 ' ' \d ** 4 )
        /, -> $/ { "{$0.trim} {$1.fmt('%02d')} $2" });
        # 2. Pad single-digit hours ('Mon, 15 Jan 2024 8:30:00 GMT').
        $s .= subst(:g, /
            ( \d ** 4 ' ' ) (\d) ':' (\d ** 2)
        /, -> $/ { "{$0}{$1.fmt('%02d')}:$2" });
        # 3. Seconds-less clock times gain ':00' ('10:00 +0000'). The
        # lookbehind keeps an already-complete 'HH:MM:SS' from being re-read
        # as 'MM:SS' and doubled.
        $s .= subst(:g, /
            <!after <[+0..9:]>> ( \d ** 2 ':' \d ** 2 ) <!before ':'>
            ( \s* <[+-]> \d ** 2 ':'? \d ** 2 )? $
        /, -> $/ { "$0:00" ~ ($1 // '') });
        # 4. Numeric offsets need a leading space and a four-digit form
        # ('+0530', not '+05:30'). Idempotent for already-valid offsets.
        $s .= subst(:g, /
            ( \d ** 2 ':' \d ** 2 ':' \d ** 2 ) \s* ( <[+-]> \d ** 2 ) ':'? ( \d ** 2 )
        /, -> $/ { "$0 $1$2" });
        # 5. Synthesize the weekday for weekday-less dates ('15 Jan 2024').
        # Bogus dates keep today's Nil behavior via the try.
        if $s !~~ / <[a..zA..Z]> ** 3 ',' / && $s ~~ / ( \d ** 1..2 ) ' ' ( <[a..zA..Z]> ** 3 ) ' ' ( \d ** 4 ) / {
            my $wd = try {
                my $month = %MONTH{ ~$1.lc };
                $month.defined ?? Date.new(+$2, $month, +$0).day-of-week !! Nil;
            };
            $s = $wd.defined ?? (<Mon Tue Wed Thu Fri Sat Sun>)[$wd - 1] ~ ", $s" !! $s;
        }
    }
    # Space-separated ISO datetimes (e.g. '2024-01-15 08:30:00 -0500') are
    # rejected by datetime-interpret; convert them to the T-separated form.
    # Seconds are optional for leniency ('2024-01-15 08:30' gains ':00').
    # The date prefix requires an ISO YYYY-MM-DD shape, so RFC 2822 dates
    # (month names) are never affected.
    $s .= subst(:g, /
        (\d ** 4 '-' \d ** 2 '-' \d ** 2) ' ' (\d ** 2 ':' \d ** 2) (':' \d ** 2)?
        ' '? (<[+-]> \d ** 2 ':'? \d ** 2)? $ /
    , { "$0T$1" ~ ($2 ?? $2 !! ':00') ~ ($3 // '') });
    # RFC 2822 date-only values ('Mon, 15 Jan 2024') have no clock time and
    # DateTime::Grammar cannot parse them; normalize to midnight UTC.
    if $s ~~ / ( \d ** 1..2 ) ' ' ( <[a..zA..Z]> ** 3 ) ' ' ( \d ** 4 ) $ /
        && $s !~~ / \d ** 1..2 ':' \d ** 2 / {
        $s ~= ' 00:00:00 GMT';
    }
    # Datetimes without any timezone designator are treated as UTC rather
    # than silently dropped. Only clock times qualify, so bare dates like
    # '2024-01-15' (which datetime-interpret already handles) are untouched.
    # ISO YYYY-MM-DD shapes append 'Z'; RFC 2822 month-name shapes are not
    # understood by DateTime::Grammar with a trailing 'Z', so they get a
    # space-separated 'GMT' instead.
    if $s ~~ / \d ** 2 ':' \d ** 2 \s* $ /
        && $s !~~ / ( 'Z' | <[+-]> \d ** 2 ':'? \d ** 2 ) \s* $ / {
        $s ~= $s ~~ / \d ** 4 '-' / ?? 'Z' !! ' GMT';
    }
    $s
}

sub parse-date(Any $str, Bool :$optional = False) is export {
    return Nil if $optional && (!$str.defined || !$str.Str.trim.chars);
    die "parse-date: empty or unset string" unless $str.defined && $str.Str.trim.chars > 0;
    my $normalized = normalize-date-str($str.Str.trim);
    # datetime-interpret throws X::Temporal::OutOfRange for
    # structurally-valid-but-invalid dates (2024-02-30, 32 Jan, 25:00) rather
    # than returning Nil; turn that into the graceful die/Nil below.
    my $dt = try { datetime-interpret($normalized) };
    without $dt {
        return Nil if $optional;
        die "parse-date: cannot parse '$str'";
    }
    apply-source-offset($dt, $normalized)
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

# Pretty-print compact, single-line XML (as XML::Element.Str produces, or any
# other well-formed XML) by re-indenting elements. Whitespace is inserted only
# at element boundaries, never inside text content, CDATA, or attribute values,
# so the output round-trips through any parser unchanged (concatenating all
# whitespace yields the original string).
#
# Both leaf and mixed-content elements are preserved exactly: an element whose
# content is only text stays on one line; an element with only element children
# puts each child on its own line; an element whose content interleaves text
# and child elements keeps every text span inline, in original order, with the
# child elements indented between them. Comments, processing instructions,
# declarations, DOCTYPE, and CDATA sections are treated as opaque nodes and
# kept verbatim. If the input cannot be cleanly tokenized or balanced, the
# original string is returned unchanged rather than emitting corrupt output.
sub indent-xml(Str $xml, Str :$indent = '  ' --> Str) is export {
    my @tok := tokenize-xml($xml) or return $xml;

    my $idx     = 0;
    my $ntok    = @tok.elems;
    my $partial = False;

    # True when the '<...>' token is a complete parenthesized construct with no
    # embedded '<' (start/empty/close tags and declarations). Comments/CDATA/
    # DOCTYPE are open-ended and handled separately (see tokenize-xml).
    my sub is-tag(Str $t) { $t.starts-with('<') && !$t.starts-with('<![CDATA[') && !$t.starts-with('<!--') }

    my sub is-close(Str $t, Str $name) { so $t ~~ /^ '</' $name \s* '>' $/ }

    # Parse a single element (its opening token is at $idx). Returns an array
    # node, or sets $partial on any structural problem so the caller bails out
    # to the un-pretty original.
    my sub parse-element() {
        my $t = @tok[$idx];
        if $t.starts-with('<?') || $t.starts-with('<!') || $t.starts-with('<!--') || $t.starts-with('<![CDATA[') {
            $idx++;
            return ['opaque', $t];
        }
        if $t.ends-with('/>') {
            $idx++;
            return ['empty', $t];
        }
        my $m    = $t ~~ /^ '<' ( <?[$A..Za..z_]> [ <?[$A..Za..z0..9_.-]> | ':' <?[$A..Za..z0..9_.-]> ]* )/;
        my $name = $m ?? ~$m[0] !! '';
        if !$name {
            $partial = True;
            return ['empty', $t];
        }

        # Collect the element's children. Precisely one '<name   >' close tag
        # closes the element; anything else that is a self/opaque child or a
        # text run is accumulated, so text may interleave with child elements.
        my @kids;
        my $buf  = '';
        my $k    = $idx + 1;
        while $k < $ntok {
            my $tk = @tok[$k];
            if is-tag($tk) {
                if is-close($tk, $name) {
                    if $buf.defined && $buf.chars {
                        @kids.push: ['text', $buf];
                    }
                    $idx = $k + 1;
                    return ['elem', $name, $t, @kids];
                }
                # A child element (or open/self-closing sibling) breaks the
                # text run; flush it, then parse the child at its own index.
                if $buf.defined && $buf.chars {
                    @kids.push: ['text', $buf];
                    $buf = '';
                }
                $idx = $k;
                @kids.push: parse-element();
                return ['elem', $name, $t, @kids] if $partial;
                $k = $idx;
                next;
            }
            $buf ~= $tk;
            $k++;
        }
        $partial = True;
        return ['elem', $name, $t, @kids];
    }

    my sub render-elem($node, $depth, @out) {
        my $pad = $indent x $depth;
        my $name = $node[1];
        my $kids = $node[3];
        my $has-element-kids = $kids.grep({ $_[0] ne 'text' }).elems > 0;
        if !$has-element-kids {
            # Text-only (leaf) or empty element: single line.
            my $text = $kids.map({ $_[0] eq 'text' ?? $_[1] !! '' }).join;
            @out.push: $pad ~ $node[2] ~ $text ~ "</$name>";
            return;
        }
        my $mixed = $kids.grep({ $_[0] eq 'text' }).elems > 0;
        @out.push: $pad ~ $node[2];
        if $mixed {
            # Keep interleaved text inline on the opener line; indent children.
            my $inline = '';
            for $kids.list -> $kid {
                if $kid[0] eq 'text' {
                    $inline ~= $kid[1];
                }
                elsif $kid[0] eq 'elem' {
                    if $inline.chars {
                        @out.push: $pad ~ $inline;
                        $inline = '';
                    }
                    render-elem($kid, $depth + 1, @out);
                }
                else {
                    if $inline.chars {
                        @out.push: $pad ~ $inline;
                        $inline = '';
                    }
                    @out.push: ($indent x ($depth + 1)) ~ $kid[1];
                }
            }
            if $inline.chars {
                @out.push: $pad ~ $inline;
            }
        }
        else {
            for $kids.list -> $kid {
                render-elem($kid, $depth + 1, @out)
                    if $kid[0] eq 'elem';
                @out.push: ($indent x ($depth + 1)) ~ $kid[1]
                    if $kid[0] eq 'opaque' || $kid[0] eq 'empty';
            }
        }
        @out.push: $pad ~ "</$name>";
    }

    my @out;
    while $idx < $ntok && !$partial {
        my $tk = @tok[$idx];
        if is-tag($tk) || $tk.starts-with('<?') || $tk.starts-with('<!--') || $tk.starts-with('<![CDATA[') {
            my $node = parse-element();
            if $partial { last }
            if $node[0] eq 'elem' {
                render-elem($node, 0, @out);
            }
            else {
                @out.push: $node[1];
            }
        }
        else {
            # Top-level stray text (e.g. an unparented whitespace run).
            @out.push: $tk if $tk ~~ /\S/;
            $idx++;
        }
    }
    return $xml if $partial;
    @out.join("\n");
}

# Tokenize XML into alternating text runs and '<...>' markup tokens. Handles
# comments (<!---->, which may contain '>' and '<'), CDATA sections (<![CDATA[
# ... ]]>, which may contain '<' and '>'), and processing/declaration/DOCTYPE
# instructions (which run to the first '>'). Returns an empty array on input
# that cannot be tokenized (unterminated construct), so callers fall back to
# the original string.
=begin comment
Internal to indent-xml; not exported.
=end comment
my sub tokenize-xml(Str $xml --> List) {
    my @tok;
    my $pos = 0;
    my $len = $xml.chars;
    while $pos < $len {
        my $lt = $xml.index('<', $pos);
        if !$lt.defined {
            @tok.push: $xml.substr($pos) if $pos < $len;
            last;
        }
        @tok.push: $xml.substr($pos, $lt - $pos) if $lt > $pos;
        if $xml.substr($lt, 9) eq '<![CDATA[' {
            my $end = $xml.index(']]>', $lt + 9);
            return List.new unless $end.defined;
            @tok.push: $xml.substr($lt, $end - $lt + 3);
            $pos = $end + 3;
            next;
        }
        if $xml.substr($lt, 4) eq '<!--' {
            my $end = $xml.index('-->', $lt + 4);
            return List.new unless $end.defined;
            @tok.push: $xml.substr($lt, $end - $lt + 3);
            $pos = $end + 3;
            next;
        }
        my $gt = $xml.index('>', $lt);
        return List.new unless $gt.defined;
        @tok.push: $xml.substr($lt, $gt - $lt + 1);
        $pos = $gt + 1;
    }
    @tok;
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
=item C<parse-date(Str, :$optional = False)> - Parse date string, dies on bad input and returns C<DateTime>; with C<:optional> returns C<DateTime> or C<Nil> for empty or unparseable input
=item C<matches-ns(XML::Element, $ns-uri, $canonical-prefix)> - Namespace membership in the element's own scope
=item C<get-text-by-ns($parent, $local-name, $ns-uri, $canonical-prefix = "")> - Get optional text of the first child matching local name and namespace URI
=item C<elements-by-local-ns($parent, $ns-uri, $local-name, $canonical-prefix)> - Namespace-aware child element lookup
=item C<sanitize($value)> - Deep clone dropping undefined slots and empty containers for safe to-hash export
=item C<indent-xml($xml, :$indent = "  ")> - Pretty-print compact single-line XML by indenting elements. Handles leaf, container, and mixed text+element content; comments, processing instructions, declarations, DOCTYPE, and CDATA are kept verbatim. Text, CDATA, and attribute values are never altered, and if the input is not cleanly tokenizable the original string is returned unchanged.

=end pod
