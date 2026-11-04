# jekyll-literate

A literate programming tool: a book written as Markdown chapters is woven into a website and tangled into files.

## Language

### Book source

**Book source**:
Every file and folder the Book is written in: its Book source files and Book source directories.
_Avoid_: Docs, literate source, web

**Book source file**:
One Markdown file of Prose and Fragments, the source of exactly one Book page. Its Fragments may write into any number of Tangled files.
_Avoid_: Document, Markdown file, page

**Book source directory**:
A folder of Book source files, always beside the Top-level book source file of the same name; its files are the Sections of that file's Chapter.
_Avoid_: Module folder, subfolder

**Top-level book source file**:
A Book source file in no Book source directory; each one opens a Chapter, and its Page title is the Chapter title.
_Avoid_: Top-level chapter, root document, intro page, index file

**Reading order**:
The one fixed order in which all Book source files are read: each Chapter's Top-level book source file, then its Sections.
_Avoid_: Sequence, navigation order

**Prose**:
The text of a Book source file outside its Fragments and Examples.
_Avoid_: Documentation, commentary, TeX part

**Fragment**:
One code block that is Tangled: either a Named fragment or a File fragment. Fragments that share a Name or file are joined in Reading order.
_Avoid_: Chunk, snippet, macro, piece, block

**Named fragment**:
A Fragment identified by a Name, which other Fragments' code References.
_Avoid_: Id block, definition

**File fragment**:
A Fragment identified by the full path of the Tangled file it writes into; nothing References it.
_Avoid_: Root, root chunk, unnamed section, file block

**Appended fragment**:
A Fragment whose Name or file an earlier Fragment in Reading order already has; its code follows theirs.
_Avoid_: Continuation, piece, addition

**Name**:
What identifies a Named fragment, written `⟨name⟩` and shown beside each Fragment that has it. Every Name is scoped to its Chapter, even a Chapter of one Book page.
_Avoid_: Label, margin note, margin name, fragment title, tag, id, global name

**Reference**:
A line of a Fragment's code that is only a Name, standing for every Named fragment with that Name.
_Avoid_: Use, use site, include, call

**Expansion**:
The code a Reference became in a Tangled file: every Named fragment it stands for, in Reading order.
_Avoid_: Inclusion, splice

**Example**:
A code block that is never Tangled, shown only to illustrate.
_Avoid_: Snippet, sample, untangled fragment

**Tangled file**:
A file generated entirely by Tangling Fragments and always named by its full path; its contents are written in the Book source, never in the file itself.
_Avoid_: Output file, generated source

**Tangle**:
To generate every Tangled file from the Fragments.
_Avoid_: Extract, export, generate

**Stitch**:
To copy edits made in a Tangled file back into the Fragments that wrote them.
_Avoid_: Untangle, sync back

### Book structure

**Book**:
The whole woven work: a Title page, a Table of contents, then its Chapters in Reading order.
_Avoid_: Site, docs, manual

**Chapter**:
A top-level division of the Book: one Top-level book source file, with the Book source directory of the same name as its Sections if there is one. Chapters are never nested.
_Avoid_: Part, volume, module

**Section**:
One Book source file in a Book source directory, as a division of that directory's Chapter. A Chapter with no Book source directory has no Sections.
_Avoid_: Page, file

**Subsection**:
The part of a Book source file from one level-2 heading up to the next, or to the file's end. What comes before the first belongs directly to the Chapter or Section; a file with no level-2 heading has no Subsections.
_Avoid_: Subheading, block, part

**Book page**:
One URL of the Book, woven from exactly one Book source file.
_Avoid_: Web page, document

**Title page**:
The first page of the Book, showing the Book title.
_Avoid_: Cover, splash page, home page

**Table of contents**:
The page after the Title page listing every Chapter and Section in Reading order.
_Avoid_: TOC, index, contents page

**Book title**:
The name of the Book, shown on its Title page.
_Avoid_: Site title

**Chapter title**:
The name of a Chapter: the Page title of its Top-level book source file.
_Avoid_: Chapter heading, module name

**Section heading**:
The name of a Section.
_Avoid_: Section title

**Subsection heading**:
The level-2 heading that opens a Subsection.
_Avoid_: Section heading, subtitle

**Page title**:
The title of a Book page: its Chapter title for a Top-level book source file, otherwise its Section heading.
_Avoid_: Title, front-matter title

### Publishing

**Weave**:
To build the Book, and the Source browser beside it, from the Book source.
_Avoid_: Build the site, render, publish

**Source browser**:
The woven view of every Tangled file, cross-referenced with the Book.
_Avoid_: Source viewer, Source, code view

**Listing**:
One Tangled file as shown in the Source browser.
_Avoid_: File page, source view

**File header**:
The tab above a Fragment or Listing that shows the full path of the Tangled file its code is in.
_Avoid_: File tab, file label

**Cross-reference**:
A link from a Name, Reference, Expansion or File header to the matching place in the Book or Source browser.
_Avoid_: Backlink, xref, jump link

**Bar**:
A rule in a Listing's margin spanning every line one Fragment wrote, the Expansions of its References included.
_Avoid_: Range marker, line bar

**Highlight**:
The tint on the Fragment, Reference or Expansion a Cross-reference arrived at.
_Avoid_: Selection, target styling, Syntax highlighting

**Syntax highlighting**:
Colouring code by the kind of each token, in Fragments, Examples and Listings alike.
_Avoid_: Highlight, colouring
