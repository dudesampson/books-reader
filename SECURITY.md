# Security and privacy

Books Reader is an experimental, unsandboxed macOS application. Its source uses Accessibility to read Apple Books and visible Christianbook browser pages and turn pages, PDFKit to read user-selected local PDFs without modifying them, and the local `/usr/bin/say` command to generate speech. There are no third-party runtime dependencies or application network calls.

Christianbook mode recognizes only HTTPS reader URLs on `library.christianbook.com` in supported browsers. It reads the embedded Publica book frame and targets its Next/Prev buttons through Accessibility. It does not access browser cookies, saved passwords, hidden application state, or EPUB download endpoints. Browser requests remain the responsibility of the browser.

## Local data

- Temporary page text and audio live in a uniquely named `BooksReader-*` directory under the macOS temporary directory.
- Stop, page changes, and normal quit remove those files. Forced termination or a crash may leave them behind. Deletion is not secure erasure.
- Window geometry and playback speed are stored in macOS preferences.
- Book title, page label, and playback timing are exposed to macOS Now Playing.
- The repository does not include books, audio, user preferences, credentials, or built applications.

The app's folder may be synced by a cloud drive if you place it in one. That is separate from the application's local speech processing.

## Reporting

Do not post credentials, private book passages, full Accessibility dumps, personal file paths, or recordings in public issues. A small synthetic example and macOS version are usually enough for an ordinary bug report.

For sensitive vulnerabilities, use the repository's **Security → Report a vulnerability** option when available. If it is unavailable, open a minimal issue asking the maintainer to enable a private reporting channel, without publishing vulnerability details.

The optional `--check-web-geometry OUTPUT_PATH` diagnostic writes Accessibility attribute names, text lengths, and geometry to a local JSON file. It does not write book passages or account credentials. Use only a local output path that you intend to share with a maintainer.
