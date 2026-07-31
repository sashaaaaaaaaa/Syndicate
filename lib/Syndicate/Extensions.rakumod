use v6.d;
use XML;
use Syndicate::Stats;

unit module Syndicate::Extensions:ver<0.0.1>:auth<zef:sasha>;

# Populated at compile-time by use-statements in parser modules.
# Runtime calls to register-ext are supported but must not race
# with concurrent run-parsers/run-generators calls.
my @ext-snapshot;
my $ext-lock = Lock.new;
my atomicint $extension-errors = 0;

our sub extension-count(--> Int) is export { @ext-snapshot.elems }

our sub extension-errors(--> Int) is export { ⚛$extension-errors }

our sub remove-last-ext(--> Nil) is export {
    $ext-lock.protect: {
        my @new = @ext-snapshot.List;
        @new.pop if @new;
        @ext-snapshot = @new;
    }
}

our sub register-ext(:&parse, :&generate, Str :$namespace?, Str :$namespace-uri?) is export {
    $ext-lock.protect: {
        my @new = @ext-snapshot.List;
        @new.push: %(:&parse, :&generate, :$namespace, :$namespace-uri);
        @ext-snapshot = @new;
    }
}

our sub run-parsers($elem, %attrs, :$active?) is export {
    my @exts = @ext-snapshot;
    return unless @exts;
    my $act = $active // set-active(@exts, $elem);
    for @exts.kv -> $i, %ext {
        next unless $act{$i};
        %ext<parse>($elem, %attrs);
        CATCH {
            when X::Control { .rethrow }
            default {
                $extension-errors⚛++;
                Syndicate::Stats.record-error;
                note "Extension parse callback failed: $_\n{.backtrace}";
            }
        }
    }
}

our sub run-generators($xml, $item, :$active?) is export {
    my @exts = @ext-snapshot;
    return unless @exts;
    for @exts.kv -> $i, %ext {
        next if $active.defined && !$active{$i};
        %ext<generate>($xml, $item);
        CATCH {
            when X::Control { .rethrow }
            default {
                $extension-errors⚛++;
                Syndicate::Stats.record-error;
                note "Extension generate callback failed: $_\n{.backtrace}";
            }
        }
    }
}

our sub active-extensions(--> List) is export { @ext-snapshot }

our sub set-active(@exts, $elem) is export {
    my @prefixes = @exts.map({ .<namespace> }).grep(*.defined);
    return @exts.keys.Set unless @prefixes;
    my %present = @prefixes.map({ $_ => False });
    my %ext-by-prefix = @exts.grep({ .<namespace>.defined }).map({ .<namespace> => $_ });

    # Thread in-scope xmlns URI bindings through the tree walk. A fresh
    # hash is built only when an element actually declares xmlns:
    # attributes; otherwise the parent's hash is shared.
    my sub with-bindings(%parent, $e) {
        my %b = %parent;
        my $declared = False;
        for $e.attribs.kv -> $k, $v {
            if $k.starts-with('xmlns:') {
                %b{$k.substr(6)} = ~$v;
                $declared = True;
            }
        }
        $declared ?? %b !! %parent
    }

    # An element using a registered prefix only counts when the prefix
    # is bound to the extension's namespace-uri (or the extension does
    # not require one).
    my sub activate($name, %bindings) {
        return unless $name.defined;
        with $name.index(':') -> $j {
            my $prefix = $name.substr(0, $j);
            my $ext = %ext-by-prefix{$prefix} or return;
            return unless %present{$prefix}:exists;
            my $uri = %bindings{$prefix};
            %present{$prefix} = True
                if !$ext.<namespace-uri>
                || ($uri.defined && $uri eq $ext.<namespace-uri>);
        }
    }

    my %b = with-bindings({}, $elem);
    activate($elem.name, %b);
    my @stack = ($elem, %b);
    my $i = 0;
    while $i < @stack.elems {
        my $e = @stack[$i++];
        next unless $e ~~ XML::Element;
        my %bindings = @stack[$i++];
        for $e.nodes -> $node {
            next unless $node ~~ XML::Element;
            my %nb = with-bindings(%bindings, $node);
            activate($node.name, %nb);
            last if so %present.values.all;
            @stack.push: $node;
            @stack.push: %nb;
        }
        last if so %present.values.all;
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
