# LastNote

A Notepad++-style text editor for macOS, with an interactive shell console at the bottom and an
optional transparent, tinted window.

- **Editor engine:** [Scintilla](https://www.scintilla.org) + Lexilla (the same engine Notepad++ uses),
  vendored in `Vendor/` with a few small patches for translucent backgrounds (see `Vendor/PATCHES.md`).
- **Console:** [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) running your login shell (`$SHELL`, usually zsh).
- **UI:** AppKit, with SwiftUI for the settings screens.

## Build & run

```bash
swift run                 # dev run (unbundled)
scripts/bundle.sh         # release build -> build/LastNote.app
open build/LastNote.app
swift test                # unit + end-to-end tests (real window, real shells)
scripts/make_icns.sh      # regenerate the app icon from scripts/make_icon.swift
```

Requires Xcode 16+ / Swift 6 toolchain, macOS 13+.

## Features

- Tabs, open/save/save as/save all, reload, recent files, session restore, Finder "Open With" support
- Syntax highlighting + code folding for ~30 languages (C/C++, C#, Java, JS/TS, Swift, Go, Kotlin, Python,
  SQL/PL-SQL, Shell, JSON, HTML, XML, CSS, Markdown, YAML, TOML, INI, Makefile, Rust, Lua, Ruby, PowerShell, Batch, Diff)
- Multi-cursor & column (⌥-drag) editing, brace matching, smart highlighting of the selected word, bookmarks
- Find / Replace bar with match case, whole word and regex, match highlighting and count
- Line operations: duplicate, delete, move up/down, join, sort, trim trailing whitespace, UPPER/lower, toggle comment
- EOL conversion (CRLF / LF / CR), encoding detection
- Console: full interactive shells in **tabs** (⌃\` show/hide, ⌃⇧\` new tab, ⌘W closes the focused console tab),
  cd to file's folder, **Run File in Console** (⌘R)
- **Tab names**: double-click any editor or console tab (or right-click / Control-click → Rename Tab…, ⇧⌘R)
  to give it a name; editor-tab names are labels only (the file isn't renamed) and are remembered per file
- **Tab colours**: every editor tab and console tab can have its own tint (right-click a tab, the palette
  icon, or ⌥⌘K); editor-tab colours are remembered per file
- **Icon bar** in the title-bar row with the most-used commands (file, clipboard, undo, find, zoom, wrap,
  show all characters, comment, bookmark, console, run, transparency, tab colour)
- **Focus glow**: a soft glowing border shows whether the cursor is in the editor or the console
  (toggle and colour in the transparency popover / Settings)
- Transparency: on/off (⌥⌘T), opacity slider, any tint colour, optional frosted-glass blur,
  dark/light text colours — from the ◐ button in the status bar or Settings (⌘,)

## Dev notes

`LASTNOTE_SNAPSHOT=/tmp/out.png LASTNOTE_SNAPSHOT_QUIT=1 swift run LastNote file.txt` writes a PNG of
the window after launch (add `LASTNOTE_SELFTEST=1` to exercise Run-in-console and Find first).
