# Vendored source

- `scintilla/` — Scintilla 5.6.7 (https://www.scintilla.org), Scintilla license (see scintilla/License.txt)
- `lexilla/` — Lexilla 5.5.4 (https://www.scintilla.org/Lexilla.html), same license

Both are compiled directly into the `SciKit` SwiftPM target. `include/` holds symlinks to the
public headers Swift needs, plus `SciBridge.h` (implemented in `bridge/`).

## Local patches (search for `[lastnote patch]`)

Translucent editor backgrounds, so the window tint/blur shows through while text stays solid:

1. `scintilla/src/Geometry.h` — added `ColourRGBA::FromIpRGBTransparency`: the unused high byte of
   a colour is read as *transparency* (0 = opaque, 255 = clear). Callers that pass plain RGB are
   unaffected.
2. `scintilla/src/Editor.cxx` — `SCI_STYLESETBACK`, `SCI_SETFOLDMARGINCOLOUR` and
   `SCI_SETFOLDMARGINHICOLOUR` use it.
3. `scintilla/cocoa/ScintillaView.mm` — `SCIContentView isOpaque` returns NO and the scroll view
   does not draw a background.

4. `scintilla/cocoa/PlatCocoa.mm` — off-screen pixmaps start clear instead of opaque white
   (otherwise the fold margin shows as a white stripe).

5. `scintilla/src/EditView.cxx` — the line-remainder and end-of-line fills keep the style's alpha
   instead of forcing `.Opaque()`.
6. `scintilla/cocoa/ScintillaView.mm` — `SCIMarginView` is non-opaque and skips NSRulerView's
   background drawing.

Bug fixes (found with Address Sanitizer + `LASTNOTE_STRESS`):

7. `scintilla/src/PositionCache.cxx` — `LineLayout::CalculatePositions` read `chars[-1]` and
   `styles[-1]` for empty lines (heap-buffer-overflow). Guarded.
8. `scintilla/src/MarginView.cxx` — when both fold-margin colours are equal, fill the margin with
   a solid colour instead of a tiled CGPattern. The pattern was the only nested drawing in a
   CoreGraphics display-list replay crash seen on macOS 26.
9. `scintilla/src/EditView.cxx` — `DrawTextBlob` draws the letters of LF/CR/control-char blobs
   in the (now transparent) back colour; use it opaque so the letters stay visible.
10. `scintilla/src/EditView.cxx` — `PaintText` could start painting at line -1 when asked to draw
   above the document (rubber-band scrolling / responsive-scrolling overdraw at the top), and
   `LayoutLine` then wrote one byte before a heap buffer. That silent heap corruption was the cause
   of LastNote's random crashes in AppKit/CoreGraphics/Metal code. The first painted line is now
   clamped to 0. `MarginView::PaintOneMargin` gets the same clamp.

When upgrading Scintilla, re-apply these.
