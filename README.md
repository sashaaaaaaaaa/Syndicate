# Syndicate

Syndication feed parser/generator for RSS 2.0 and Atom 1.0.

## Usage

```raku
use Syndicate;

# Parse RSS
my $rss = parse-rss($xml-string);
say $rss.title;
say $rss.items[0].title;

# Parse Atom
my $atom = parse-atom($xml-string);
say $atom.title;
say $atom.items[0].title;

# Create RSS feed
my $feed = Syndicate::RSS.new(
    :title("My Feed"),
    :link("http://example.com"),
    :description("A test feed"),
    :items([
        Syndicate::RSS::Item.new(
            :title("Item 1"),
            :link("http://example.com/1"),
        ),
    ]),
);
say ~$feed;  # XML output

# Create Atom feed
my $atom-feed = Syndicate::Atom.new(
    :title("My Atom Feed"),
    :id("http://example.com/atom"),
    :updated(DateTime.now),
);
say ~$atom-feed;  # XML output
```
