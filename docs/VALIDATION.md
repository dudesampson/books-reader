# Validation

## Environment

Developed on Apple silicon with macOS 26. Repository packaging uses Apple Swift 6.3.2 and targets macOS 13 or later. Earlier macOS versions and Intel hardware have not been tested.

## Automated checks

The build script runs the executable with `--self-test` before packaging. Tests cover:

- Text segmentation, empty input, segment lengths, and word preservation.
- Seeking across prepared audio segments and clamping at their boundaries.
- Forward/back 15-second seeking.
- Idempotent play/pause commands and toggle behavior.
- Restoring 0.75×/0.85× speeds and migrating the original four saved speed choices without changing their values.

These tests do not require Accessibility permission and do not verify Apple Books UI automation or physical headset routing.

## Manual checks during development

- Reading and automatic page transitions were exercised with a readable Apple Books book. Automatic transition testing included seeking near the end to invoke the actual completion callback.
- Pause/resume and backward skips were confirmed by the user.
- Compact and regular layouts were checked by dragging window corners. Controls remained visible at the minimum size, including wrapped permission guidance.
- The user confirmed the Mission Control fix using a hot corner and successfully moved the reader between screens.

## Remaining coverage

Physical AirPods commands, previous-page navigation, forward skip controls, and behavior across additional books need broader end-to-end testing. Existing media routing depends on which app macOS selects as the active player. There is no claim of compatibility with every Apple Books format or sample.
