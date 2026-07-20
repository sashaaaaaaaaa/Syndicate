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

sub register-ext(:&parse, :&generate, Str :$namespace?, Str :$namespace-uri?) is export {
    $ext-lock.protect: {
        my @new = @ext-snapshot.List;
        @new.push: %(:&parse, :&generate, :$namespace, :$namespace-uri);
        @ext-snapshot = @new;
    }
}

sub run-parsers($elem, %attrs, :$active?) is export {
    my @exts = @ext-snapshot;
    return unless @exts;
    my $act = $active // set-active(@exts, $elem);
    for @exts.kv -> $i, %ext {
        next unless $act{$i};
        %ext<parse>($elem, %attrs);
        CATCH {
            when X::Control { .rethrow }
            default {
                Syndicate::Stats.record-error;
                note "Extension parse callback failed: $_\n{.backtrace}";
            }
        }
    }
}

sub run-generators($xml, $item, :$active?) is export {
    my @exts = @ext-snapshot;
    return unless @exts;
    for @exts.kv -> $i, %ext {
        next if $active.defined && !$active{$i};
        %ext<generate>($xml, $item);
        CATCH {
            when X::Control { .rethrow }
            default {
                Syndicate::Stats.record-error;
                note "Extension generate callback failed: $_\n{.backtrace}";
            }
        }
    }
}

sub all-descendant-elements($n) {
    gather {
        my @stack = $n;
        my $i = 0;
        while $i < @stack.elems {
            my $e = @stack[$i++];
            next unless $e ~~ XML::Element;
            take $e;
            @stack.push: $e.nodes.Slip if $e ~~ XML::Element;
        }
    }
}

sub active-extensions(--> List) is export { @ext-snapshot }

sub set-active(@exts, $elem) is export {
    my @prefixes = @exts.map({ .<namespace> }).grep(*.defined);
    return @exts.keys.Set unless @prefixes;
    my %present = @prefixes.map({ $_ => False });
    my $check = $elem.name;
    with $check.index(':') -> $i {
        %present{$check.substr(0, $i)} = True;
    }
    for all-descendant-elements($elem).skip(1) -> $e {
        my $name = $e.name;
        with $name.index(':') -> $i {
            my $prefix = $name.substr(0, $i);
            %present{$prefix} = True if %present{$prefix}:exists;
        }
        last if so %present.values.all;
    }
    # Second pass: check xmlns: attributes on the element itself.
    # These are checked after the descendant name loop because they
    # are the authoritative declaration — but they can only set a
    # prefix to True (never back to False).
    for $elem.attribs.kv -> $k, $v {
        with $k.index('xmlns:') {
            my $prefix = $k.substr(6);
            next unless %present{$prefix}:exists;
            my $uri-ok = so @exts.first({
                .<namespace> eq $prefix && (!.<namespace-uri> || .<namespace-uri> eq $v)
            });
            %present{$prefix} = True if $uri-ok;
        }
    }
    @exts.kv.map(-> $i, %ext { $i if !%ext<namespace> || %present{%ext<namespace>} }).grep(*.defined).Set
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

=head2 C<remove-last-ext>

Removes the most recently registered extension. Designed for test
teardown only. Must not be called concurrently with C<run-parsers>
or C<run-generators>.

=head2 C<run-parsers($elem, %attrs)>

Runs all registered parse callbacks. Called during RSS item parsing.
The extension snapshot is read atomically; concurrent calls to
C<remove-last-ext> during parsing are unsupported.

=head2 C<run-generators($xml, $item)>

Runs all registered generate callbacks. Called during RSS item XML output.
Same atomic-read caveat as C<run-parsers>.

=end pod
