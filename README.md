# jekyll-literate

A literate programming tool built on [Entangled](https://entangled.github.io/) and
[Jekyll](https://jekyllrb.com). A book written as Markdown chapters is tangled into files by
Entangled and woven by this gem into a website: a title page, a table of contents, the chapters
in reading order, and a source browser of every tangled file, cross-referenced with the book.

It is a Jekyll theme (layouts, includes, Sass, fonts) and a plugin (the weave) in one gem, plus
a `literate` command that tangles and then runs Jekyll. Terms used here (book source, chapter,
section, fragment, name, …) are defined in [GLOSSARY.md](GLOSSARY.md); decisions are recorded
in `docs/adr/`.

## Setting up a book

A book's repository needs the book source, an Entangled config and three small files at its
root:

```
book/                    the book source
entangled.toml           Entangled configuration (watch_list = ["book/**/*.md"])
Gemfile
_config.yml
.ruby-version            e.g. 4.0.9
```

```ruby
# Gemfile
source "https://rubygems.org"

gem "jekyll-literate", git: "https://github.com/jonsnyder01/jekyll-literate", branch: "main",
                       group: :jekyll_plugins
```

```yaml
# _config.yml
title: My book
subtitle: A literate program
description: Shown in search results.

theme: jekyll-literate
source: book
destination: build/site
```

Then, from the book's root:

```sh
bundle config set --local path vendor/bundle && bundle install   # first time
bundle exec literate serve       # tangle, then weave and preview at http://localhost:4000
bundle exec literate build       # tangle, then weave into the destination
bundle update jekyll-literate    # take a newer version of the tool
```

`literate` runs `entangled tangle`, then `jekyll build` or `jekyll serve` with `_config.yml`;
further arguments go to Jekyll. Jekyll does not watch the tangled files, so while previewing run
`entangled watch` alongside `literate serve`; a listing refreshes on the next rebuild.

### Configuration

The theme's `_config.yml` holds the defaults; a book's own `_config.yml` overrides any of them.

| Setting | Default | Meaning |
|---|---|---|
| `literate.tangle_dir` | `src` | where Entangled writes the tangled files, from the book's root; the source browser is at `/<tangle_dir>/` |
| `sass` | compressed, no source maps | the stylesheet build |

A book overrides a layout, include or Sass partial by putting its own copy at the same path in
its book source: for example `book/_sass/literate/_settings.scss` to change the type scale, or
`book/_includes/footer.html`.

## Writing a chapter

A chapter is a top-level book source file `NN-<name>.md`, plus, if it has sections, a book
source directory `NN-<name>/` beside it holding one `NN-<section>.md` per section. The `NN-`
prefixes set the reading order and are dropped from URLs (`book/02-strbuf/01-growth.md` is
`/strbuf/growth/`). Chapters cannot be nested, and a directory without its `.md` is refused.

Every book source file needs a `title:`: the chapter title in a top-level file, the section
heading in a section. Its `##` headings start subsections. Names are scoped to their chapter
(see `docs/adr/0001-names-scoped-to-their-chapter.md`), so every file with fragments sets the
chapter's name as its Entangled namespace, and the weave refuses it otherwise:

```markdown
---
title: "Growing the buffer"
entangled:
  version: "2.5"
  namespace: strbuf
---
```

Fragments use Entangled's *basic* style: a plain language fence, with attributes in leading
`//|` comment lines (`#|` for shell and Python). The book shows a file header with the tangled
file's full path above each fragment, and a named fragment's name beside it, noweb style. A
`file:` is always the full path from the book's root.

````markdown
```c
//| file: src/strbuf/growth.c
#include "module.h"
<<reserve>>
```

```c
//| id: reserve
static void strbuf_reserve(StrBuf *buffer, size_t extra) { … }
```
````

Repeating an `id` makes an appended fragment (shown as `⟨id⟩ +≡`). Other chapters can reference
a name as `<<strbuf::reserve>>`. Use `~~~` fences for examples that must not be tangled.

A fence's language must be one Entangled knows. Others are declared in `entangled.toml`, and the
weave reads them from there too, to find their attribute lines:

```toml
[[languages]]
name = "Ruby"
identifiers = ["ruby"]
comment = { open = "#" }

[[languages]]
name = "HTML"
identifiers = ["html"]
comment = { open = "<!--", close = "-->" }
```

Book source files are not rendered with Liquid, so a fragment can hold a Liquid template; a file
that wants Liquid sets `render_with_liquid: true` in its front matter.

## The book and the source browser

The book opens on a generated title page (`/`), then a table of contents (`/contents/`) of every
chapter and its sections in reading order. The source browser (`/src/`) shows the tangled files:
a file tree beside a listing of each one. Each fragment's file header in the book links to its
lines in the listing (`/src/<file>/#<anchor>`, highlighted while targeted), each name in the
listing links back to its fragment in the book, and each reference links to its expansion. All
of these cross-references are built from the `~/~ begin`/`~/~ end` annotations Entangled writes
into the tangled files, which the listing hides.

The layout and type scale live in `_sass/literate/_base.scss`: the text column is exactly as wide
as a code block (80 characters of Source Code Pro), names sit in a left margin on windows of
960px and up, and sizes step up at 960, 1024, 1080, 1280 and 1536px, always whole pixels at the
default 16px. Line heights are the `$text-leading` and `$code-leading` ratios in
`_sass/literate/_settings.scss`.

## Publishing from GitHub Actions

`.github/workflows/book.yml` is a reusable workflow that installs Ruby and Entangled, runs
`bundle exec literate build`, and on pushes to the default branch deploys the destination to
Cloudflare Pages. A book calls it from its own workflow:

```yaml
jobs:
  site:
    uses: jonsnyder01/jekyll-literate/.github/workflows/book.yml@main
    with:
      cloudflare-project: my-book       # omit to only build
    secrets: inherit                    # CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID
```

Inputs: `entangled-version` (default `2.5.0`), `destination` (default `build/site`) and
`cloudflare-project`. The deploy is skipped with a warning until `CLOUDFLARE_API_TOKEN` exists.

## Developing the gem

To try changes against a book without pushing them, point Bundler at a local checkout (the
book's Gemfile must name `branch: "main"`):

```sh
bundle config set --global local.jekyll-literate ~/dev/jekyll-literate
```

The weave is `lib/jekyll-literate/literate.rb` (book source files, chapters, fragments, the
title page and table of contents) and `lib/jekyll-literate/source.rb` (the source browser).

The SCSS in `_sass/` is formatted with [Prettier](https://prettier.io/): one property per line,
4-space indents, no tabs (`.prettierrc.json`; `.editorconfig` gives editors the same indent):

```sh
npx prettier@3.9.10 --write "_sass/**/*.scss"     # or --check to only report
```

## Credits

The theme began as [tufte-jekyll](https://github.com/clayh53/tufte-jekyll) (MIT, see
`LICENSE-tufte-jekyll`); its syntax-highlighting colours remain, the rest has been replaced.
Text is set in [Source Serif 4](https://github.com/adobe-fonts/source-serif), file headers in
[Source Sans 3](https://github.com/adobe-fonts/source-sans) and code in
[Source Code Pro](https://github.com/adobe-fonts/source-code-pro), Adobe's variable fonts under
the SIL Open Font License 1.1 (see `assets/fonts/*/LICENSE.md`).
