# Validation

## Environment

Developed on Apple silicon with macOS 26. Repository packaging uses Apple Swift 6.3.2 and targets macOS 13 or later. Earlier macOS versions and Intel hardware have not been tested.

## Automated checks

The build script runs the executable with `--self-test` before packaging. Tests cover:

- Text segmentation, empty input, segment lengths, and word preservation.
- Seeking across prepared audio segments and clamping at their boundaries.
- Forward/back 15-second seeking.
- Idempotent play/pause commands and toggle behavior.
- PDF passage-to-source ranges, Unicode text preservation, repeated page text, blank-page skipping, and document boundaries, using a generated in-memory PDF.
- Restoring 0.75×/0.85× speeds and migrating the original four saved speed choices without changing their values.

These tests do not require Accessibility permission and do not verify Apple Books UI automation or physical headset routing.

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
