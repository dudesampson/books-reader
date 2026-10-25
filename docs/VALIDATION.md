# Validation

## Environment

Developed on Apple silicon with macOS 26. Repository packaging uses Apple Swift 6.3.2 and targets macOS 13 or later. Earlier macOS versions and Intel hardware have not been tested.

## Automated checks

The build script runs the executable with `--self-test` before packaging. Tests cover:

- Christianbook URL matching, book-viewport clipping, page boundaries, and Unicode word preservation.
- Text segmentation, empty input, segment lengths, and word preservation.
- Seeking across prepared audio segments and clamping at their boundaries.
- Forward/back 15-second seeking.
- Idempotent play/pause commands and toggle behavior.
- PDF passage-to-source ranges, Unicode text preservation, repeated page text, blank-page skipping, and document boundaries, using a generated in-memory PDF.
- Restoring 0.75×/0.85× speeds and migrating the original four saved speed choices without changing their values.

These tests do not require Accessibility permission and do not verify live browser/Apple Books UI automation or physical headset routing.

## Manual checks during development

- Reading and automatic page transitions were exercised with a readable Apple Books book. Automatic transition testing included seeking near the end to invoke the actual completion callback.
- Pause/resume and backward skips were confirmed by the user.
- Compact and regular layouts were checked by dragging window corners. Controls remained visible at the minimum size, including wrapped permission guidance.
- The user confirmed the Mission Control fix using a hot corner and successfully moved the reader between screens.

- A local 18-page text PDF passed text preservation and selection-range checks on every page (`BooksReader --check-pdf /path/to/document.pdf`). The document is not included in the repository.
- PDF passage highlighting and Window-menu navigation were visually checked.
- Live PDF playback, pause, backward 30/60-second and forward 30/60-second skips, automatic advancement from page 1 to page 2 via the actual audio completion callback, and Previous Page back to page 1 were exercised.

## Remaining coverage

Physical AirPods commands, Apple Books previous-page navigation, and behavior across additional books and PDF layouts need broader end-to-end testing. Existing media routing depends on which app macOS selects as the active player. There is no claim of compatibility with every Apple Books format or sample.

## Christianbook compatibility

The adapter targets the Christianbook embedded Publica reader. Version 3.6 clips individual word positions to the book's containing viewport and reads displayed pages. It presses the reader's own Next/Prev controls and waits for a stable new page before starting audio. Automated tests cover exclusion of header/footer text and offscreen columns, preservation across adjacent pages, Unicode offsets, and missing position data. Browser engine variations, reader layout changes, image-only pages, and non-Christianbook readers require separate verification.

Earlier version 3.5 live checks on 2026-10-25 used the signed-in Christianbook/Publica edition of *The Soulwinner* in Brave:

- Chapter 1 narration started through the new Christianbook source.
- Next Chapter selected Chapter 2 through the site's table of contents; Previous Chapter returned to Chapter 1 with the contents menu initially closed.
- Pause and backward 15-second seeking worked, leaving playback paused at 0:00 in Chapter 1.
- With Continue to next chapter enabled, seeking to the end of the prepared Preface audio triggered the real audio-completion callback, selected Chapter 1, and began preparing its narration.
- The image-only title section reported no readable chapter instead of narrating unrelated browser controls.
- The installed UI was visually checked at its compact window size. Safari, Chrome, Edge, other books, and end-of-book live behavior remain unverified.

Version 3.6 live checks on 2026-10-25 used the same book in Brave:

- The book viewport was 870 × 737 screen points, distinct from the surrounding 870 × 929 reader. The diagnostic confirmed the ancestor chain includes `readiumViewport`.
- Next Page advanced between displayed pages within Chapter 1; Previous Page reversed that transition. The displayed paragraph positions were inspected independently through the browser DOM.
- Seeking from 2:08 to the end of a fully prepared 2:38 page invoked the actual audio-completion callback, pressed Next, changed the displayed text, and started preparing the next page at 0:00.
- Pause worked after the transition, with Automatically turn pages still enabled.
- A paragraph crossing a visual page break was assigned to the preceding page by browser Accessibility. The following page began with the next paragraph, preserving narration order at that tested boundary. Turns can therefore lag a visual break until the paragraph finishes; exact word-to-screen synchronization is not claimed.
- One macOS `say` subprocess stalled during preparation; restarting with Read visible page completed the page audio. This remains a speech-engine limitation rather than a page-turn verification pass for every synthesis attempt.
