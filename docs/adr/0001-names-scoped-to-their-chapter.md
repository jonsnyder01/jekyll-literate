# Names are scoped to their chapter, even in a chapter of one page

Every name belongs to the chapter it is defined in: a chapter with sections and a chapter that is a single top-level book source file alike. There are no global names, so a reference to another chapter's fragment is always qualified (`<<strbuf::reserve>>`). Entangled sets a namespace per Markdown file from its front matter and otherwise defaults to one global namespace, so the weave refuses any book source file with fragments whose `entangled: namespace:` is not its chapter's name, and refuses two chapters with the same name. We chose this over keeping top-level book source files global (the noweb and Entangled default) so that a chapter's names never depend on whether it has sections: splitting a one-page chapter into sections, or merging one back, changes no references. It also keeps the scoping independent of this book's C convention that a chapter with sections is a module, because the tool is meant to outgrow that convention.

## Consequences

A chapter's name (its top-level book source file's name without the `NN-` prefix and `.md`) is part of every qualified reference into it, so renaming a chapter means updating those references.
