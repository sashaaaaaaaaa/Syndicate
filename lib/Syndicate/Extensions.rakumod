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

sub extension-count(--> Int) is export { @ext-snapshot.elems }

sub extension-errors(--> Int) is export { ⚛$extension-errors }

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
                $extension-errors⚛++;
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
                $extension-errors⚛++;
                Syndicate::Stats.record-error;
                note "Extension generate callback failed: $_\n{.backtrace}";
            }
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
    # Walk descendants to find which namespace prefixes are actually
    # used in the element tree, and check xmlns: declarations on all
    # elements (not just root). Inlined instead of calling a gather/take
    # sub to avoid Seq allocation overhead.
    {
        my @stack = $elem;
        my $max = 10_000;
        my $i = 0;
        while $i < @stack.elems {
            die "all-descendant-elements: exceeded $max element limit" if $i >= $max;
            my $e = @stack[$i++];
            next unless $e ~~ XML::Element;
            if $i > 1 {
                my $name = $e.name;
                with $name.index(':') -> $j {
                    my $prefix = $name.substr(0, $j);
                    %present{$prefix} = True if %present{$prefix}:exists;
                }
                # Check xmlns: attributes on descendant elements
                for $e.attribs.kv -> $k, $v {
                    with $k.index('xmlns:') {
                        my $prefix = $k.substr(6);
                        next unless %present{$prefix}:exists;
                        my $uri-ok = so @exts.first({
                            .<namespace> eq $prefix && (!.<namespace-uri> || .<namespace-uri> eq $v)
                        });
                        %present{$prefix} = True if $uri-ok;
                    }
                }
                last if so %present.values.all;
            }
            @stack.append: $e.nodes;
        }
    }
    # Third pass: check xmlns: attributes on root element.
    # These are checked after the descendant walk because they
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
