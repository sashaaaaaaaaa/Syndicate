use v6.d;

use Syndicate::Item;
use Syndicate::Feed;
use Syndicate::Config;
use Syndicate::RSS;
use Syndicate::RSS::Item;
use Syndicate::RSS::V0_91;
use Syndicate::RSS::V0_91::Item;
use Syndicate::RSS::V1_0;
use Syndicate::RSS::V1_0::Item;
use Syndicate::Atom;
use Syndicate::Atom::Item;
use Syndicate::JSONFeed;
use Syndicate::JSONFeed::Item;
use Syndicate::Utils;
use Syndicate::Builder::Feed;
use Syndicate::Builder::Entry;
use Syndicate::Parse;
use Syndicate::Extension::DublinCore;
use Syndicate::Extension::MediaRSS;
use Syndicate::Discovery;

unit class Syndicate:ver<0.0.1>:auth<zef:sasha>;

sub parse(Str $input --> Any) is export {
    parse-feed($input)
}

sub parse-rss(Str $xml) is export {
    Syndicate::RSS.new($xml)
}

sub parse-atom(Str $xml) is export {
    Syndicate::Atom.new($xml)
}
