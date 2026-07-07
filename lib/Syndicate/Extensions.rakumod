use v6.d;
use XML;
use Syndicate::Stats;

unit module Syndicate::Extensions:ver<0.0.1>:auth<zef:sasha>;

# Populated at compile-time by use-statements in parser modules.
# Runtime calls to register-ext are supported but must not race
# with concurrent run-parsers/run-generators calls.
my @ext-snapshot;
my $ext-lock = Lock.new;

sub extension-count(--> Int) is export { @ext-snapshot.elems }

sub remove-last-ext(--> Nil) is export {
    $ext-lock.protect: {
        my @new = @ext-snapshot.List;
        @new.pop if @new;
        @ext-snapshot = @new;
    }
}

sub register-ext(:&parse, :&generate, Str :$namespace?) is export {
    $ext-lock.protect: {
        my @new = @ext-snapshot.List;
        @new.push: %(:&parse, :&generate, :$namespace);
        @ext-snapshot = @new;
    }
}

sub run-parsers($elem, %attrs) is export {
    my @exts := @ext-snapshot;
    return unless @exts;
    my $active = set-active(@exts, $elem);
    for @exts.kv -> $i, %ext {
        next unless $active{$i};
        %ext<parse>($elem, %attrs);
        CATCH {
            when X::Control { .rethrow }
            default {
                Syndicate::Stats.record-error;
                note "Extension parse callback failed: $_";
            }
        }
    }
}

sub run-generators($xml, $item) is export {
    my @exts := @ext-snapshot;
    return unless @exts;
    for @exts -> %ext {
        %ext<generate>($xml, $item);
        CATCH {
            when X::Control { .rethrow }
            default {
                Syndicate::Stats.record-error;
                note "Extension generate callback failed: $_";
            }
        }
    }
}

sub set-active(@exts, $elem) {
    my @prefixes = @exts.map({ .<namespace> }).grep(*.defined);
    return @exts.keys.Set unless @prefixes;
    my %present = @prefixes.map({ $_ => False });
    my $check = $elem.name;
    with $check.index(':') -> $i {
        %present{$check.substr(0, $i)} = True;
    }
    for $elem.nodes.grep(XML::Element) -> $e {
        my $name = $e.name;
        with $name.index(':') -> $i {
            my $prefix = $name.substr(0, $i);
            %present{$prefix} = True if %present{$prefix}:exists;
        }
    }
    for $elem.attribs.kv -> $k, $v {
        with $k.index('xmlns:') {
            my $prefix = $k.substr(6);
            %present{$prefix} = True if %present{$prefix}:exists;
        }
    }
    @exts.kv.map(-> $i, %ext { $i if !%ext<namespace> || %present{%ext<namespace>} }).Set
}

=begin pod

=head1 NAME

Syndicate::Extensions - Extension registration registry

=head1 DESCRIPTION

Central registry for feed format extensions. Extensions register
parse/generate callbacks that run automatically during RSS item
parsing and XML generation.

B<Note:> All RSS parsers (RSS 0.91, RSS 1.0, RSS 2.0) unconditionally
load the DublinCore, MediaRSS, and ITunes extensions at compile time.
There is currently no opt-out mechanism to disable individual extensions.

=head1 EXPORTED SUBS

=head2 C<register-ext(:&parse, :&generate)>

Register an extension. C<&parse> receives an XML::Element and a mutable
hash of attributes. C<&generate> receives an XML::Element and the item
object.

=head2 C<run-parsers($elem, %attrs)>

Runs all registered parse callbacks. Called during RSS item parsing.

=head2 C<run-generators($xml, $item)>

Runs all registered generate callbacks. Called during RSS item XML output.

=end pod
