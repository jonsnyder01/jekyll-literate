# frozen_string_literal: true

# Weaves the book source (Jekyll's source directory, e.g. book/) into a book:
#
# - every .md file in it is a book source file, laid out with book-page
#   unless it names another layout, and not rendered with Liquid (its
#   fragments may be Liquid templates themselves) unless it asks to be;
# - permalinks drop the NN- ordering prefixes (02-strbuf/01-growth.md -> /strbuf/growth/);
# - each top-level book source file opens a chapter, whose sections are the
#   files in the book source directory of the same name (02-strbuf.md and
#   02-strbuf/); a directory without its file, or a directory inside a
#   directory, is refused;
# - the reading order is the sorted path order of the book source (a
#   chapter's file sorts before its directory), exposed as
#   site.data.reading_order and as page.previous / page.next;
# - a title page is generated at / and a table of contents at /contents/;
# - each fragment's Entangled attributes (the leading `//| id:` / `//| file:`
#   lines) are removed from the code; a file header with the tangled file's
#   full path goes above it, and a named fragment's name beside it, noweb
#   style: `⟨name⟩ ≡` for the first fragment with that name, `⟨name⟩ +≡` for
#   an appended fragment;
# - names are scoped to their chapter: a book source file with fragments must
#   set its chapter's name as its Entangled namespace;
# - each fragment gets a stable anchor and its file header links to its lines
#   in the source browser (see source.rb), which links back to that anchor.

require "cgi"
require "pathname"
require "tomlrb"
require "yaml"

module Literate
  CONTENTS_URL = "/contents/"

  # Comment openers of Entangled 2.5's built-in languages, by fence
  # language; Entangled reads `<opener>| key: value` lines as attributes.
  COMMENTS = {
    "awk" => "#", "gawk" => "#", "mawk" => "#", "nawk" => "#", "sh" => "#", "bash" => "#",
    "c" => "//", "cpp" => "//", "c++" => "//", "python" => "#", "rust" => "//",
    "haskell" => "--", "ocaml" => "(*", "ml" => "(*",
    "scheme" => ";", "r5rs" => ";", "r6rs" => ";", "r7rs" => ";", "racket" => ";", "clojure" => ";",
    "julia" => "#", "java" => "//", "pure" => "--", "purs" => "--", "purescript" => "--",
    "css" => "/*", "lua" => "--", "make" => "#", "makefile" => "#", "gnuplot" => "#",
    "toml" => "#", "yaml" => "#", "fsharp" => "//", "javascript" => "//", "js" => "//",
    "ecma" => "//", "go" => "//", "golang" => "//", "r" => "#", "rlang" => "#", "nix" => "#",
  }.freeze

  # The built-in languages plus those the book declares under `[[languages]]`
  # in entangled.toml, in the directory the book is built in.
  def self.comments
    return COMMENTS unless File.exist?("entangled.toml")

    declared = Tomlrb.load_file("entangled.toml").fetch("languages", [])
    declared.each_with_object(COMMENTS.dup) do |language, found|
      language.fetch("identifiers", []).each { |id| found[id] = language.dig("comment", "open") }
    end
  end

  OPEN_FENCE = /\A(?<indent>\s*)```(?<lang>[^\s`{]+)\s*\z/
  CLOSE_FENCE = /\A\s*```\s*\z/
  IGNORE_FENCE = /\A\s*~~~/

  def self.book_source_file?(page)
    page.ext == ".md"
  end

  # A book source file's path as written in errors and in Entangled's
  # annotations: from the directory the book is built in (02-strbuf.md ->
  # book/02-strbuf.md).
  def self.project_path(site, relative_path)
    Pathname.new(site.in_source_dir(relative_path)).relative_path_from(Pathname.pwd).to_s
  end

  def self.strip_prefix(name)
    name.sub(/\A\d+-/, "")
  end

  # 02-strbuf/01-growth.md -> ["02-strbuf", "01-growth"]
  def self.path_parts(relative_path)
    relative_path.delete_suffix(".md").split("/")
  end

  # 02-strbuf/01-growth.md -> /strbuf/growth/
  def self.permalink(relative_path)
    "/" + path_parts(relative_path).map { |part| strip_prefix(part) }.join("/") + "/"
  end

  # The name of the chapter a book source file belongs to: its book source
  # directory's, or its own for a top-level book source file.
  def self.chapter_name(relative_path)
    strip_prefix(path_parts(relative_path).first)
  end

  # A section is a book source file in a book source directory.
  def self.section?(relative_path)
    path_parts(relative_path).size > 1
  end

  # "/strbuf/growth/" -> "strbuf-growth"; also used for names in anchors.
  def self.slug(text)
    text.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
  end

  # Entangled's naming: a name is qualified by the book source file's
  # namespace unless it already is (`strbuf::grow`) or the file has none.
  def self.qualify(name, namespace)
    name.include?("::") || namespace.nil? ? name : "#{namespace}::#{name}"
  end

  # A fragment's key is [book source file, qualified name, number]; its
  # anchor and URL in the book follow from the key alone.
  def self.fragment_url(key)
    permalink(key[0])
  end

  def self.fragment_anchor(key)
    md, qualified, count = key
    "#{slug(permalink(md))}--#{slug(qualified.split("::").last)}#{"-#{count + 1}" if count.positive?}"
  end

  # Id of a reference: the line in one fragment's code that is another's name.
  def self.reference_anchor(referrer_anchor, qualified)
    "#{referrer_anchor}--references-#{slug(qualified)}"
  end

  # Rewrites every fragment in a book source file's Markdown. `book` carries
  # state across book source files, read in order: the names already defined
  # (to tell appended fragments from first ones), where each fragment landed
  # among the tangled files, and the anchors recorded for the source browser.
  def self.render_fragments(page, book)
    book_page = {
      md: page.relative_path, path: project_path(page.site, page.relative_path), namespace: page.data.dig("entangled", "namespace"),
      chapter: chapter_name(page.relative_path), title: page.data["title"], url: page.url,
      counts: Hash.new(0),
    }
    markdown = page.content
    lines = markdown.lines
    out = []
    i = 0
    while i < lines.size
      line = lines[i]

      # ~~~ blocks are examples (and ignored by Entangled): copy them verbatim.
      if line.match?(IGNORE_FENCE)
        out << line
        i += 1
        while i < lines.size
          out << lines[i]
          i += 1
          break if lines[i - 1].match?(IGNORE_FENCE)
        end
        next
      end

      open = line.chomp.match(OPEN_FENCE)
      unless open
        out << line
        i += 1
        next
      end

      close = (i + 1...lines.size).find { |j| lines[j].chomp.match?(CLOSE_FENCE) } || lines.size
      body = lines[i + 1...close]
      attributes = {}
      if (comment = book[:comments][open[:lang]])
        attribute_line = /\A#{Regexp.escape(open[:indent] + comment)}\s*\|(.*)\z/m
        header = body.take_while { |l| l.match?(attribute_line) }
        unless header.empty?
          attributes = YAML.safe_load(header.map { |l| l.match(attribute_line)[1] }.join) || {}
          body = body.drop(header.size)
        end
      end

      # File header, name and code share one wrapper (kramdown still parses
      # the fence inside it): the name follows the header so that, floated
      # into the margin, it lines up with the first line of code, and all of
      # it highlights together when the fragment's anchor is targeted.
      anchor, header, name = fragment_parts(attributes, book_page, book)
      if anchor
        out << "#{open[:indent]}<div class=\"fragment\" id=\"#{anchor}\" markdown=\"1\">\n\n"
        out << "#{open[:indent]}#{header}\n\n" if header
        out << "#{open[:indent]}#{name}\n\n" if name
      end
      out << line
      # A reference is written `⟨name⟩` before the code is highlighted: as
      # `<<name>>` a lexer may take it for code (a Ruby heredoc, say) and
      # misread the lines after it.
      out.concat(anchor ? body.map { |l| l.sub(REFERENCE_SOURCE, "\\1⟨\\2⟩") } : body)
      out << lines[close] if close < lines.size
      out << "\n#{open[:indent]}</div>\n" if anchor
      i = close + 1
    end
    out.join
  end

  # What is rendered around a fragment's code: its anchor; a file header with
  # the full path of the tangled file it is in, linking to its lines in the
  # source browser; and, for a named fragment, its name `⟨name⟩ ≡`.
  # A file fragment gets the file header only.
  def self.fragment_parts(attributes, book_page, book)
    id = attributes["id"]&.to_s
    file = attributes["file"]&.to_s
    return [nil, nil, nil] unless id || file

    unless book_page[:namespace] == book_page[:chapter]
      raise "#{book_page[:path]}: names are scoped to their chapter; set `namespace: #{book_page[:chapter]}` " \
            "under `entangled:` in its front matter"
    end

    # Entangled identifies a fragment by its id, or failing that its target
    # file, qualified by the namespace unless already qualified, and numbers
    # repeated names within one book source file from 0. That triple is the
    # key written into its `~/~ begin` annotations in the tangled files.
    name = id || file
    qualified = qualify(name, book_page[:namespace])
    operator = book[:defined].include?(qualified) ? "+≡" : "≡"
    book[:defined] << qualified
    count = book_page[:counts][qualified]
    book_page[:counts][qualified] += 1
    key = [book_page[:md], qualified, count]

    display = name.split("::").last
    anchor = fragment_anchor(key)
    book[:anchors][key] = {
      "anchor" => anchor, "name" => display, "file" => id.nil?, "appended" => operator == "+≡",
      "title" => book_page[:title], "url" => book_page[:url],
    }
    location = book[:locations][key]

    # A file fragment whose file an earlier fragment already started is appended to it.
    path = location || file
    appended = id.nil? && operator == "+≡" ? " <em>(continued)</em>" : ""
    header =
      if location
        %(<div class="file-header"><a href="#{Source.url(location)}##{anchor}"><code>#{CGI.escapeHTML(location)}</code>#{appended}</a></div>)
      elsif path
        %(<div class="file-header"><code>#{CGI.escapeHTML(path)}</code>#{appended}</div>)
      end
    if id
      # The name links to the reference to it in another fragment's code.
      name_html = "⟨#{CGI.escapeHTML(id)}⟩"
      if (referrer = book[:referrers][key])
        href = "#{fragment_url(referrer)}##{reference_anchor(fragment_anchor(referrer), qualified)}"
        name_html = %(<a href="#{href}">#{name_html}</a>)
      end
      # The operator has a slot of its own, so that in the margin the names
      # line up on their `⟩` whether it is `≡` or `+≡`.
      name_div = %(<div class="fragment-name">#{name_html}<span class="fragment-op"> #{operator}</span></div>)
    end
    [anchor, header, name_div]
  end

  # Refuses a book source directory without the top-level book source file
  # that opens its chapter.
  def self.check_chapters(site, pages)
    paths = pages.map(&:relative_path).to_set
    pages.map(&:relative_path).select { |path| section?(path) }.each do |path|
      directory = path_parts(path).first
      next if paths.include?("#{directory}.md")

      shown = project_path(site, directory)
      raise "#{shown}/: a book source directory needs #{shown}.md beside it to open its chapter"
    end
  end

  class Generator < Jekyll::Generator
    safe true
    priority :highest

    def generate(site)
      pages = site.pages.select { |page| Literate.book_source_file?(page) }.sort_by(&:relative_path)
      Literate.check_chapters(site, pages)

      listings = Source.read(site)
      book = {
        defined: Set.new, anchors: {}, comments: Literate.comments,
        locations: Source.locations(listings), referrers: Source.referrers(listings),
      }
      pages.each { |page| page.content = Literate.render_fragments(page, book) }
      # For mark_references, after rendering: each fragment's anchor -> its file.
      Literate.source_paths = book[:anchors].to_h { |key, a| [a["anchor"], book[:locations][key]] }

      title_page = generated_page(site, "", "title-page", site.config["title"])
      contents = generated_page(site, Literate::CONTENTS_URL.delete("/"), "table-of-contents", "Contents")

      reading_order = pages.map { |page| { "title" => page.data["title"], "url" => page.url } }
      pages.each_with_index do |page, index|
        page.data["previous"] = index.positive? ? reading_order[index - 1] : link(contents)
        page.data["next"] = reading_order[index + 1]
      end
      title_page.data["next"] = link(contents)
      contents.data["previous"] = link(title_page)
      contents.data["next"] = reading_order.first
      site.data["reading_order"] = reading_order

      # Each chapter, opened by its top-level book source file, with its sections.
      chapters = {}
      pages.each do |page|
        name = Literate.chapter_name(page.relative_path)
        if Literate.section?(page.relative_path)
          chapters[name]["sections"] << link(page)
          page.data["chapter"] = chapters[name]
        else
          # Its name is the chapter's namespace, so it must be the only one.
          raise "#{Literate.project_path(site, page.relative_path)}: another chapter is already named #{name}" if chapters.key?(name)

          chapters[name] = link(page).merge("sections" => [])
        end
      end
      site.data["chapters"] = chapters.values

      site.pages << title_page << contents

      Source.generate(site, listings, book[:anchors])
    end

    private

    def generated_page(site, dir, layout, title)
      page = Jekyll::PageWithoutAFile.new(site, site.source, dir, "index.html")
      page.data["layout"] = layout
      page.data["title"] = title
      page
    end

    def link(page)
      { "title" => page.data["title"], "url" => page.url }
    end
  end
end

module Literate
  class << self
    attr_accessor :source_paths
  end

  FRAGMENT_CODE = %r{(<div class="fragment" id="([^"]+)">.*?<pre class="highlight"><code>)(.*?)(</code></pre>)}m
  # A reference as written in a fragment, and as render_fragments leaves it
  # for the highlighter.
  REFERENCE_SOURCE = /\A(\s*)<<([^<>]+)>>(?=\s*\z)/
  REFERENCE_LINE = /\A\s*⟨([^⟨⟩]+)⟩\s*\z/

  # Rewrites each reference (a line that is only `⟨name⟩`) in an anchored
  # span, in the notation of the names beside fragments. The name links to
  # the source browser, where the reference's expansion is highlighted.
  def self.mark_references(html, namespace)
    html.gsub(FRAGMENT_CODE) do
      before, referrer_anchor, code, after = $1, $2, $3, $4
      seen = Set.new
      lines = code.split("\n", -1).map do |line|
        text = CGI.unescapeHTML(line.gsub(/<[^>]+>/, ""))
        reference = text.match(REFERENCE_LINE)
        balanced = line.scan(/<span\b/).size == line.scan("</span>").size
        next line unless reference && balanced

        name = reference[1].strip
        id = reference_anchor(referrer_anchor, qualify(name, namespace))
        ref = "⟨#{CGI.escapeHTML(name)}⟩"
        if (path = source_paths&.dig(referrer_anchor))
          ref = %(<a href="#{Source.url(path)}##{id}">#{ref}</a>)
        end
        line = %(#{text[/\A\s*/]}<span class="reference-name">#{ref}</span>)
        seen.add?(id) ? %(<span class="fragment-reference" id="#{id}">#{line}</span>) : line
      end
      before + lines.join("\n") + after
    end
  end
end

Jekyll::Hooks.register :pages, :post_render do |page|
  next unless Literate.book_source_file?(page)

  page.output = Literate.mark_references(page.output, page.data.dig("entangled", "namespace"))
end

# Permalinks must be set before anything asks a page for its URL.
Jekyll::Hooks.register :pages, :post_init do |page|
  next unless Literate.book_source_file?(page)

  path = page.relative_path
  shown = Literate.project_path(page.site, path)
  raise "#{shown}: a book source file needs a `title:` in its front matter" unless page.data["title"]
  raise "#{shown}: chapters cannot be nested; a book source directory holds only files" if Literate.path_parts(path).size > 2

  page.data["layout"] ||= "book-page"
  page.data["render_with_liquid"] = false unless page.data.key?("render_with_liquid")
  page.data["permalink"] = Literate.permalink(path)
  page.data["section"] = Literate.section?(path)
end
