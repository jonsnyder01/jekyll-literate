# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "jekyll-literate"
  spec.version = "0.1.0"
  spec.summary = "Weaves an Entangled literate program into a Jekyll book with a source browser"
  spec.authors = ["Jonathan Snyder"]
  spec.homepage = "https://github.com/jonsnyder01/jekyll-literate"
  spec.required_ruby_version = ">= 3.1"

  # It is both a theme (layouts, includes, Sass, assets and a _config.yml of
  # defaults, all read from the gem's root) and a plugin (lib/).
  spec.files = Dir["{_config.yml,_includes/**/*,_layouts/**/*,_sass/**/*,assets/**/*,lib/**/*,exe/*}",
                   "LICENSE-tufte-jekyll", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["literate"]

  spec.add_dependency "jekyll", "~> 4.4"
  spec.add_dependency "kramdown-parser-gfm", "~> 1.1"
  spec.add_dependency "rouge", "~> 4.5"
  # `jekyll serve` needs a web server; Ruby 3+ no longer bundles one.
  spec.add_dependency "webrick", "~> 1.9"
end
