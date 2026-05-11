use v6.d;

use Syndicate::Item;
use Syndicate::Feed;
use Syndicate::Config;
use Syndicate::RSS;
use Syndicate::RSS::Item;
use Syndicate::RSS::V0_91;
use Syndicate::RSS::V0_91::Item;
use Syndicate::Atom;
use Syndicate::Atom::Item;
use Syndicate::Utils;
use Syndicate::Builder::Feed;
use Syndicate::Builder::Entry;

unit class Syndicate:ver<0.0.1>:auth<zef:sasha>;

sub parse-rss(Str $xml) is export {
    Syndicate::RSS.new($xml)
}

sub parse-atom(Str $xml) is export {
    Syndicate::Atom.new($xml)
}
