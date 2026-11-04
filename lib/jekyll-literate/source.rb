# frozen_string_literal: true

# Builds the source browser at /<tangle_dir>/ (/src/ by default): one page per
# tangled file, with the tangle directory's tree in a sidebar.
#
# Entangled's annotations (`// ~/~ begin <<book/…/x.md#name>>[n]` … `// ~/~ end`)
# record which fragment every line came from. They are removed from the
# listing and turned into nested, anchored line ranges, so a fragment in the
# book can link straight to its lines (highlighted with :target). Like a
# fragment in the book, the listing has a file header with the file's full
# path, and each named fragment's name, linking back to it in the book, sits
# in the left margin beside a bar over its lines, bars for nested fragments
# stacking outward (on narrow windows the name sits on a line of its own above
# the code instead).
# Run `entangled tangle` first: `literate build` does.

require "cgi"
require "pathname"
require "rouge"

module Literate
  module Source
    BEGIN_MARK = %r{\A\s*(?://|#) ~/~ begin <<(?<md>[^#]+)#(?<name>.+)>>\[(?<count>init|\d+)\]\s*\z}
    END_MARK = %r{\A\s*(?://|#) ~/~ end\s*\z}

    LEXERS = { ".c" => "c", ".h" => "c", ".sh" => "shell" }.freeze

    Listing = Struct.new(:path, :lines, :ranges, keyword_init: true)
    # `first` and `last` index the listing's lines (inclusive); `depth` is nesting.
    LineRange = Struct.new(:key, :first, :last, :depth, keyword_init: true)

    # "src/strbuf/growth.c" -> "/src/strbuf/growth.c/"
    def self.url(path)
      "/#{path}/"
    end

    # The tangle directory, from the directory the book is built in, as
    # Entangled sees it: the paths shown for tangled files start with it.
    def self.tangle_dir(site)
      site.config.dig("literate", "tangle_dir") || "src"
    end

    def self.read(site)
      dir = tangle_dir(site)
      unless Dir.exist?(dir)
        Jekyll.logger.warn "Source:", "no #{dir}/ directory; run `entangled tangle` to build the source browser"
        return []
      end
      Dir.glob("**/*", base: dir).sort.filter_map do |relative|
        full = File.join(dir, relative)
        parse(site, "#{dir}/#{relative}", File.read(full)) if File.file?(full)
      end
    end

    # Splits a tangled file into its code lines and the fragment ranges that
    # its annotations describe. "init" marks the first fragment with a name,
    # which is always number 0 within its book source file. Annotations give
    # the book source file from the directory the book is built in; keys use
    # its path in the book source, as Jekyll does.
    def self.parse(site, path, text)
      source = Pathname.new(site.source)
      lines = []
      ranges = []
      open = []
      text.each_line(chomp: true) do |line|
        if (mark = line.match(BEGIN_MARK))
          count = mark[:count] == "init" ? 0 : mark[:count].to_i
          md = Pathname.new(File.expand_path(mark[:md])).relative_path_from(source).to_s
          open << [[md, mark[:name], count], lines.size]
        elsif line.match?(END_MARK) && !open.empty?
          key, first = open.pop
          ranges << LineRange.new(key: key, first: first, last: lines.size - 1, depth: open.size)
        else
          lines << line
        end
      end
      Listing.new(path: path, lines: lines, ranges: ranges.reject { |r| r.last < r.first })
    end

    # Fragment key -> the first file it was tangled into.
    def self.locations(listings)
      listings.each_with_object({}) do |listing, found|
        listing.ranges.each { |range| found[range.key] ||= listing.path }
      end
    end

    # Fragment key -> the fragment whose code references it: the innermost
    # range around its lines in the first file it was tangled into.
    def self.referrers(listings)
      found = {}
      walk = lambda do |node|
        node[:children].each do |child|
          found[child[:range].key] ||= node[:range].key if node[:range]
          walk.(child)
        end
      end
      listings.each { |listing| tree(listing.ranges).each(&walk) }
      found
    end

    def self.generate(site, listings, anchors)
      return if listings.empty?

      dir = tangle_dir(site)
      paths = listings.map(&:path)
      reading_order = site.data["reading_order"].each_with_index.to_h { |s, i| [s["url"], i] }
      index_rows = listings.map do |listing|
        book_pages = tangled_from(listing, anchors, reading_order)
        site.pages << page(site, listing.path, url(listing.path), {
          "title" => listing.path, "file_tree" => tree_html(dir, paths, listing.path), "tangled_from" => book_pages,
        }, render(listing, anchors))
        [listing.path, book_pages]
      end
      site.pages << page(site, dir, url(dir), {
        "title" => "#{dir}/", "file_tree" => tree_html(dir, paths, nil),
      }, index_html(index_rows))
    end

    def self.page(site, dir, permalink, data, content)
      page = Jekyll::PageWithoutAFile.new(site, site.source, dir, "index.html")
      # The listing is code: Liquid must not see `{{` or `{%` in it.
      page.data.merge!(data, "layout" => "source", "permalink" => permalink, "render_with_liquid" => false)
      page.content = content
      page
    end

    # The book pages a tangled file was tangled from, in reading order.
    def self.tangled_from(listing, anchors, reading_order)
      listing.ranges.filter_map { |range| anchors[range.key] }
             .uniq { |a| a["url"] }
             .sort_by { |a| reading_order.fetch(a["url"], Float::INFINITY) }
             .map { |a| { "title" => a["title"], "url" => a["url"] } }
    end

    def self.render(listing, anchors)
      lexer = Rouge::Lexer.find(LEXERS[File.extname(listing.path)].to_s) ||
              Rouge::Lexer.guess_by_filename(listing.path) || Rouge::Lexers::PlainText
      lexer = lexer.new if lexer.is_a?(Class)
      formatter = Rouge::Formatters::HTMLLinewise.new(Rouge::Formatters::HTML.new, class: "line")
      source = listing.lines.empty? ? "" : listing.lines.join("\n") + "\n"
      html_lines = formatter.format(lexer.lex(source)).split(%r{(?<=</div>)})
                            .map { |l| l.delete_prefix('<div class="line">').sub(%r{\n?</div>\z}, "") }

      nodes = tree(listing.ranges)
      context = {
        text: listing.lines, html: html_lines, anchors: anchors, used: Set.new, out: +"",
        spacers: spacers(nodes, listing.lines, anchors), row: 0, line_rows: {}, spacer_rows: {},
      }
      render_node({ range: nil, first: 0, last: listing.lines.size - 1, children: nodes }, context)
      <<~HTML
        <div class="source-listing">#{header(listing, anchors)}<div class="source-code">
        #{margin(nodes, context)}
        <pre class="highlight"><code>#{context[:out]}</code></pre>
        </div></div>
      HTML
    end

    # The file header: the file's full path, linking to the fragment in the
    # book that starts the file.
    def self.header(listing, anchors)
      start = listing.ranges.sort_by(&:first).filter_map { |r| anchors[r.key] }
                     .find { |a| a["file"] && !a["appended"] }
      path = "<code>#{CGI.escapeHTML(listing.path)}</code>"
      path = %(<a href="#{start["url"]}##{start["anchor"]}">#{path}</a>) if start
      %(<div class="file-header">#{path}</div>)
    end

    # Nests the (properly nested) ranges: each node's children are the ranges
    # directly inside it, in line order.
    def self.tree(ranges)
      top = []
      stack = []
      ranges.sort_by { |r| [r.first, r.depth] }.each do |range|
        stack.pop while stack.any? && stack.last[:last] < range.first
        node = { range: range, first: range.first, last: range.last, children: [] }
        (stack.empty? ? top : stack.last[:children]) << node
        stack << node
      end
      top
    end

    # A fragment's own lines interleaved with its inner fragments. Each line
    # belongs to the innermost fragment that wrote it, so in CSS a targeted
    # fragment highlights only its own lines. For narrow windows a fragment's
    # name sits inline above its code, and is repeated in italic wherever a
    # named fragment resumes after an inner one.
    def self.render_node(node, context)
      range = node[:range]
      anchor = range && context[:anchors][range.key]
      text = context[:text]
      out = context[:out]
      blank = ->(i) { text[i].strip.empty? }

      if range
        id = anchor && context[:used].add?(anchor["anchor"]) ? %( id="#{anchor["anchor"]}") : ""
        out << %(<span class="fragment-range"#{id}>)
        if shows_name?(anchor)
          out << inline_name(anchor, text[first_code(node, text) || node[:first]])
        end
        if context[:spacers].include?(node.object_id)
          context[:spacer_rows][node.object_id] = context[:row]
          context[:row] += 1
          out << %(<span class="line spacer"> </span>)
        end
      end

      resume = false
      children = node[:children].dup
      line = node[:first]
      while line <= node[:last]
        if (child = children.first) && child[:first] == line
          # A reference expands to every fragment with its name, one after
          # another: wrap them so that the book's `⟨name⟩` can target the
          # whole expansion, with the same id as the reference in the book.
          expanded = [children.shift]
          while (succ = children.first) && succ[:first] == expanded.last[:last] + 1 &&
                succ[:range].key[1] == child[:range].key[1]
            expanded << children.shift
          end
          expansion = anchor && Literate.reference_anchor(anchor["anchor"], child[:range].key[1])
          expansion = nil unless expansion && context[:used].add?(expansion)
          out << %(<span class="fragment-expansion" id="#{expansion}">) if expansion
          expanded.each { |fragment| render_node(fragment, context) }
          out << "</span>" if expansion
          line = expanded.last[:last] + 1
          resume = anchor && !anchor["file"]
          next
        end
        if resume && !blank.(line)
          out << inline_name(anchor, text[line], resumed: true)
          resume = false
        end
        context[:line_rows][line] = context[:row]
        context[:row] += 1
        html = context[:html][line]
        out << %(<span class="line">#{html.empty? ? " " : html}</span>)
        line += 1
      end
      out << "</span>" if range
    end

    # Named fragments, and fragments appended to a file, show a name; a
    # file's first fragment is named by the file header instead.
    def self.shows_name?(anchor)
      anchor && (!anchor["file"] || anchor["appended"])
    end

    def self.first_code(node, text)
      (node[:first]..node[:last]).find { |i| !text[i].strip.empty? }
    end

    # Fragments showing a name whose first line of code is also the first of
    # such a fragment inside them. Each gets a spacer: an empty, unnumbered
    # row above that line, so that every fragment's name and bar start on a
    # row of their own.
    def self.spacers(nodes, text, anchors)
      starts = Hash.new { |hash, line| hash[line] = [] }
      walk = lambda do |list|
        list.each do |node|
          first = first_code(node, text)
          starts[first] << node if first && shows_name?(anchors[node[:range].key])
          walk.(node[:children])
        end
      end
      walk.(nodes)
      starts.values.flat_map { |chain| chain[0...-1] }.to_set(&:object_id)
    end

    # A name, linking to its fragment in the book: `⟨name⟩`, then a `+` for an
    # appended fragment (`+≡` in the book), in a slot that is there either way
    # so that names line up on their `⟩`; or `(continued)` for a fragment
    # appended to a file. A name resumed after an inner fragment has no `+`.
    def self.name_link(anchor, resumed: false)
      name =
        if anchor["file"]
          "(continued)"
        else
          "⟨#{CGI.escapeHTML(anchor["name"])}⟩"
        end
      plus = anchor["appended"] && !anchor["file"] && !resumed ? "+" : ""
      %(<a href="#{anchor["url"]}##{anchor["anchor"]}">#{name}<span class="fragment-plus">#{plus}</span></a>)
    end

    def self.name_classes(anchor, resumed)
      "fragment-name#{" continued" if resumed || anchor["file"]}"
    end

    def self.inline_name(anchor, line_text, resumed: false)
      indent = line_text[/\A */].size
      %(<span class="#{name_classes(anchor, resumed)}" style="padding-left: #{indent}ch">) +
        "#{name_link(anchor, resumed: resumed)}</span>"
    end

    # The left margin: the name of each fragment that shows one, and a bar
    # from its first row to its last line of code, inner fragments included. Bars stack
    # outward from the code, the outermost fragment's nearest; the names form
    # one column left of all the bars, each level with the top of its bar.
    # Rows are the listing's lines plus its spacers.
    def self.margin(nodes, context)
      text = context[:text]
      rows = context[:line_rows]
      deepest = -1
      items = +""
      walk = lambda do |list, depth|
        list.each do |node|
          anchor = context[:anchors][node[:range].key]
          named = shows_name?(anchor)
          code = (node[:first]..node[:last]).reject { |i| text[i].strip.empty? }
          if named && code.any?
            top = context[:spacer_rows].fetch(node.object_id, rows[code.first])
            deepest = [deepest, depth].max
            items << %(<span class="#{name_classes(anchor, false)}" style="top: calc(#{top} * var(--code-leading))">) +
                     "#{name_link(anchor)}</span>"
            items << %(<span class="fragment-bar" style="--depth: #{depth}; top: calc(#{top} * var(--code-leading)); ) +
                     %(height: calc(#{rows[code.last] - top + 1} * var(--code-leading))"></span>)
          end
          walk.(node[:children], named && code.any? ? depth + 1 : depth)
        end
      end
      walk.(nodes, 0)
      %(<div class="source-margin" style="--bars: #{deepest + 1}">#{items}</div>)
    end

    def self.index_html(rows)
      body = rows.map do |path, book_pages|
        links = book_pages.map { |p| %(<a href="#{p["url"]}">#{CGI.escapeHTML(p["title"])}</a>) }.join(", ")
        %(<tr><td><a href="#{url(path)}"><code>#{CGI.escapeHTML(path)}</code></a></td><td>#{links}</td></tr>)
      end.join("\n")
      <<~HTML
        <p>Every file here is tangled from the book. Pick one from the tree, or from the table below with the book pages it comes from.</p>
        <table class="source-index"><thead><tr><th>File</th><th>Tangled from</th></tr></thead>
        <tbody>
        #{body}
        </tbody></table>
      HTML
    end

    # Nested <ul> of the tangle directory, directories expanded, the current file marked.
    def self.tree_html(dir, paths, current)
      tree = {}
      paths.each do |path|
        *dirs, file = path.delete_prefix("#{dir}/").split("/")
        node = dirs.reduce(tree) { |n, dir| n[dir + "/"] ||= {} }
        node[file] = path
      end
      %(<a class="tree-root#{" current" if current.nil?}" href="#{url(dir)}">#{dir}/</a>) + tree_list(tree, current)
    end

    def self.tree_list(node, current)
      items = node.sort_by { |name, _| name.delete_suffix("/") }.map do |name, child|
        if child.is_a?(Hash)
          %(<li class="dir"><details open><summary>#{CGI.escapeHTML(name)}</summary>#{tree_list(child, current)}</details></li>)
        else
          %(<li class="file#{" current" if child == current}"><a href="#{url(child)}">#{CGI.escapeHTML(name)}</a></li>)
        end
      end
      "<ul>#{items.join}</ul>"
    end
  end
end
