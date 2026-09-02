# API Cleanup Plan for Syndicate

## Change 1: Replace stringly-typed `convert` with enum + named subs

**Files:** `lib/Syndicate.rakumod`, `t/35-convert.rakutest`, pod

**Current** (`lib/Syndicate.rakumod:50-63`):
```raku
sub convert(Str $input, Str $to --> Str) is export {
    given $to.lc { when 'rss' | 'rss2' | 'rss2.0' { ... } ... }
}
```

**New:**
```raku
# Primary: typed enum argument
sub convert(Str $input, FeedFormat $to --> Str) is export { ... }

# Convenience aliases
sub convert-to-rss(Str $input --> Str)   is export { convert($input, RSS2) }
sub convert-to-atom(Str $input --> Str)  is export { convert($input, Atom) }
sub convert-to-json(Str $input --> Str)  is export { convert($input, JSONFeedFmt) }
sub convert-to-rss1(Str $input --> Str)  is export { convert($input, RSS1) }
sub convert-to-rss091(Str $input --> Str) is export { convert($input, RSS091) }
```

- Remove the string `when` dispatch inside `convert`; use the enum directly to call the correct builder method.
- Remove the old string aliases (`'rss2'`, `'rss2.0'`, `'rss0.91'`, `'rss1.0'`) -- the enum covers these.
- **Backward compat:** The old `convert($str, 'rss')` call will now fail at dispatch (enum coercion), which is intentional -- it's a breaking change but at v0.0.4 that's acceptable. Document in pod.
- Update `t/35-convert.rakutest`: change `convert($src-str, 'rss')` to `convert($src-str, RSS2)` etc.; add tests for `convert-to-rss`, `convert-to-atom`, etc.; remove alias tests (lines 354-358).

---

## Change 2: Introduce `FeedResult` class for `parse-feed-with-format`

**Files:** new `lib/Syndicate/FeedResult.rakumod`, `lib/Syndicate/Parse.rakumod`, `lib/Syndicate.rakumod`

**New class** (`lib/Syndicate/FeedResult.rakumod`):
```raku
unit class Syndicate::FeedResult;
has FeedFormat $.format;
has Syndicate::Feed $.feed;
```

**Update `parse-feed-with-format`** (`lib/Syndicate/Parse.rakumod:165`):
```raku
# Before: return ($format, $feed);
# After:
return Syndicate::FeedResult.new(:$format, :$feed);
```

- Change the return type annotation from `--> List` to `--> Syndicate::FeedResult:D`.
- Update all callers: `t/19-followup-audit.rakutest:36` (qualified call), pod examples.
- Destructuring changes from `my ($format, $feed) = ...` to `my $result = ...; $result.format; $result.feed`.
- Export `FeedResult` from `Syndicate` so `use Syndicate` gives access to the type.

**Implementation notes (Change 2 applied):**
- The enum `FeedFormat` was moved out of `Syndicate::Parse` into the new
  `lib/Syndicate/Format.rakumod` to break a compile cycle (`Parse` -> `FeedResult`
  -> `Parse`). `Syndicate::Parse` re-exports the enum + its members via
  `our constant ... is export = Syndicate::Format::FeedFormat::...`. `our` (not
  `my`) keeps them package-scoped so qualified access like
  `Syndicate::Parse::RSS2` and `Syndicate::Parse::FeedFormat` keeps working in
  the tests. The top-level `Syndicate` re-exports them with `my constant`
  (bare use, no qualified lookups needed there).
- **META6.json must be updated** to add the two new modules to `provides`:
  `"Syndicate::FeedResult": "lib/Syndicate/FeedResult.rakumod"` and
  `"Syndicate::Format": "lib/Syndicate/Format.rakumod"`. Without this, `zef install`
  stages only META-listed files and the freshly added modules are missing at
  install time: "Could not find Syndicate::Format".

---

## Change 3: Unify `parse-date` and `parse-date-optional`

**Files:** `lib/Syndicate/Utils.rakumod`, plus Sitemap project files (see below)

**Current** (`lib/Syndicate/Utils.rakumod:420-442`):
```raku
sub parse-date(Str $str --> DateTime) is export { ... }        # dies
sub parse-date-optional(Any $str) is export { ... }            # returns Nil
```

**New:**
```raku
sub parse-date(Str $str, Bool :$optional = False) is export {
    return Nil if $optional && (!$str.defined || !$str.trim.chars);
    die "parse-date: empty or unset string" unless $str.defined && $str.trim.chars > 0;
    my $normalized = normalize-date-str($str.trim);
    my $dt = try { datetime-interpret($normalized) };
    without $dt {
        return Nil if $optional;
        die "parse-date: cannot parse '$str'";
    }
    apply-source-offset($dt, $normalized)
}
```

- **Delete `parse-date-optional` entirely** -- no wrapper, no deprecation shim. The only
  consumers are two files in the Sitemap project, which we will update in the same pass.
- **Sitemap call sites to migrate** (in `~/Projects/programming/raku/Sitemap`):
  - `lib/Sitemap/InputParser.rakumod:254` -- `parse-date-optional($pub-el.textContent)` -> `parse-date($pub-el.textContent, :optional)`
  - `lib/Sitemap/InputParser.rakumod:309` -- `parse-date-optional($text)` -> `parse-date($text, :optional)`
  - `lib/Sitemap/InputParser.rakumod:349` -- `parse-date-optional($pub-date)` -> `parse-date($pub-date, :optional)`
  - `lib/Sitemap/Crawler.rakumod:1297` -- `parse-date-optional($date-str)` -> `parse-date($date-str, :optional)`
- Update Sitemap pod/docs if they reference `parse-date-optional`.
- Run Syndicate and Sitemap test suites to verify.

---

## Change 4: Split Builder `category` into `add-category` / `categories`

**Files:** `lib/Syndicate/Builder/Feed.rakumod`, `lib/Syndicate/Builder/Entry.rakumod`

**Current** (`lib/Syndicate/Builder/Feed.rakumod:68-71`):
```raku
method category(Str $v?) {
    @!categories.push: $v if $v.defined;
    @!categories.List
}
```

**New:**
```raku
method add-category(Str $v) {
    @!categories.push: $v;
    self
}
method categories() { @!categories.List }
```

- Same change in `Entry.rakumod:79-82`.
- Update all callers in `Builder/Feed.rakumod` (`new-from-feed` uses `$b.category($_)` -- change to `$b.add-category($_)`).
- Update `Builder/Entry.rakumod` callers similarly.
- Update pod docs and test files that call `.category(...)`.
- The method now returns `self` from `add-category` for chaining: `$fb.add-category("Tech").add-category("News")`.

---

## Change 5: Re-export `parse-file` from `use Syndicate`

**Status: CANCELLED** -- Do not implement. Verified during Change 2 that the
enum move (and the general `use Syndicate` vs `use Syndicate::Parse` split)
already causes a hard ambiguity: if a caller does both `use Syndicate` and
`use Syndicate::Parse` and calls `parse-file($str)`, Raku reports
"Ambiguous call to 'parse-file(Str)'" because two *different* `is export` subs
share the name (one in `Syndicate`, one in `Syndicate::Parse`). Attempts to
re-export the *same* code object via `sub EXPORT` don't surface `parse-file`
to `use Syndicate`-only consumers, so the only sound options were to live with
the ambiguity footgun or drop the re-export. `parse-file` keeps working fine
with `use Syndicate::Parse` on its own. Keeping it out of the top-level
`Syndicate` is also consistent: the other `Syndicate::Parse` subs (`feed-format`,
`parse-feed`, `sanitize-input`) are likewise NOT re-exported from `Syndicate`.

**Files:** `lib/Syndicate.rakumod` (no change)

The original plan (for reference) was:

```raku
sub parse-file(\arg) is export {
    Syndicate::Parse::parse-file(|arg)
}
```

- Update pod to document `parse-file` in the top-level EXPORTED SUBS section.

---

## Change 6: Add `.to-builder` convenience method on `Syndicate::Feed`

**Files:** `lib/Syndicate/Feed.rakumod`

```raku
method to-builder() {
    require Syndicate::Builder::Feed;                 # runtime load, see note
    Syndicate::Builder::Feed.new-from-feed(self)
}
```

- Convenience so callers can do `$feed.to-builder.rss-str` instead of `Syndicate::Builder::Feed.new-from-feed($feed).rss-str`.
- Low risk, purely additive.
- **Implementation note:** uses a runtime `require` rather than a compile-time
  reference / `use`, because `Builder::Feed` imports `Syndicate::Feed`; a
  compile-time reference from `Feed` back to `Builder::Feed` would be a circular
  dependency. `require` loads the builder lazily at call time, avoiding the cycle.

---

## Execution Order

1. **Change 4** (Builder category split) -- mechanical, no new types
2. **Change 3** (parse-date unification) -- small, self-contained; also update Sitemap's 4 call sites and run Sitemap tests
3. **Change 2** (FeedResult class) -- new file + update Parse
4. **Change 1** (convert with enum + named subs) -- largest change, touches tests
5. **Change 5** (re-export parse-file) -- tiny, just Syndicate.rakumod
6. **Change 6** (to-builder on Feed) -- one-liner
7. Run full test suite (Syndicate and Sitemap) to verify
