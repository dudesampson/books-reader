# Books Reader

A small macOS companion that reads the visible page in Apple Books aloud, with playback controls and automatic page turns.

Built to make assigned reading easier to listen to. This is an experimental personal project, developed with AI assistance. It is not affiliated with Apple and does not run on iPhone or iPad.

## Features

- Local speech using the macOS `say` command; no API key or cloud speech service.
- Pause/resume, a seek bar, and backward/forward skips of 15, 30, or 60 seconds.
- Playback speeds of 1×, 1.25×, 1.5×, and 2×.
- Previous/next page buttons and optional automatic page turns.
- macOS Now Playing integration for media keys and AirPods controls.
- A resizable, compact player that stays above normal windows and appears in Mission Control.

## Build and install

You need a Mac and Apple's Xcode Command Line Tools (including Swift). Install the tools with `xcode-select --install` if needed. The build targets macOS 13 or later for the architecture of the Mac running the build. Testing so far has been on Apple silicon with macOS 26; earlier versions and Intel Macs are unverified.

```sh
git clone https://github.com/dudesampson/books-reader.git
cd books-reader
./Source/build.command
```

The script compiles the source, runs its self-tests, and creates `dist/Books Reader.app`. It does not download dependencies. You can also double-click `Source/build.command` in Finder.

1. Move the generated app to a stable location, such as your Applications folder, then open it.
2. In **System Settings → Privacy & Security → Accessibility**, add and enable **Books Reader**.
3. Open a readable page in Apple Books, then click **Read Page**.

The app is not Developer ID signed or notarized. Rebuilding or moving it may require removing and re-adding its Accessibility entry. Keep one installed copy to avoid confusing different builds. A build from this repository has bundle identifier `io.github.dudesampson.booksreader`; early personal builds used a different identifier.

## Controls

| Control | Action |
| --- | --- |
| Center button / Space | Read the visible page when stopped; pause or resume when reading |
| Stop / Escape | Stop playback and cancel audio preparation |
| Back/forward 15, 30, 60 seconds | Seek within prepared audio on the current page |
| Timeline | Seek within the prepared portion of the current page |
| Previous Page / Next Page | Turn the page in Apple Books and start reading it |
| Read visible page | Restart the page currently visible in Apple Books |
| Automatically turn pages | Continue after the current page finishes |

Keyboard shortcuts apply while Books Reader is active. Time skips use audio time: at 2×, 30 seconds of audio plays in 15 seconds. Skips cannot cross page boundaries or reach audio that is still being prepared. A `+` beside the duration means more audio is being generated.

The opening passage is generated first so playback can begin while the rest is prepared. There is still a preparation gap at page boundaries. Pause retains your position for the current session; Stop starts over on the next Read Page. Closing the window quits the app.

Drag an edge or corner to resize. Controls become smaller in a compact window, and the app remembers its window frame and selected speed.

## AirPods and media keys

Starting playback registers the reader with macOS Now Playing. It handles play, pause, toggle, and stop commands. Next/previous track commands are mapped to forward/back 15 seconds within the current page; the physical gesture depends on your headphones.

macOS chooses which app receives media commands. A browser video or another player can take over. Pause the other media, then use the reader's playback button to resume its session. Physical headset routing still needs broader testing.

## Privacy and permissions

Reading and speech generation happen locally. The application contains no analytics, account login, API keys, or network requests.

Accessibility is a powerful macOS permission. This app uses it to read text exposed by Apple Books and turn pages with targeted left/right key events. Automatic page turns bring Apple Books to the foreground. Only grant the permission to a build you trust.

Page text and generated audio are temporarily written under the macOS temporary directory in a uniquely named `BooksReader-*` folder. These files are removed on Stop, page change, and normal quit. A crash or forced quit can leave files behind; this is ordinary deletion, not secure erasure. Book titles and page labels are shared with **macOS Now Playing**, where system media controls can display them.

No books, recordings, personal coursework, compiled apps, or development archives are included in this repository. See [SECURITY.md](SECURITY.md) for reporting guidance.

This project has not undergone an independent security audit. AI assistance was used during development; reading does not send your book text to an AI service.

## Content and voice permissions

The MIT license covers this project's code. It does not grant rights to book content, Apple's software, or Apple's system voices. Use only content you are authorized to process, and follow the terms that apply to your content and macOS version.

[Apple's Media Services terms, section F](https://www.apple.com/legal/internet-services/itunes/us/terms.html) restrict automated scraping and copying of service content. How those restrictions apply to this Accessibility-based reading workflow has not been legally reviewed. Accessibility access and the absence of DRM circumvention do not establish permission for every use with purchased books.

[The macOS Tahoe license, section 2F](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf) restricts system-voice use, including public sharing and commercial contexts. Do not assume generated narration can be published or sold. For a public demonstration, use your own sample text and a silent recording or your own spoken narration, rather than including the app's generated audio.

This is an experimental reading companion, not a service for creating or distributing audiobooks. These notes identify limitations; they are not legal clearance.

## Limitations

The reader uses the text Apple Books exposes through Accessibility. Image-only pages, some PDFs, and some book layouts may not work. It does not extract protected book files or bypass DRM. A visible two-page spread is treated as one reading unit.

Keep the intended book window open; if several readable book windows are open, the app may select another one. Reading a single open book is recommended. If you manually change pages while listening, use Read visible page to synchronize again.

If a page turn does not produce new readable text, the app stops rather than repeating indefinitely. This can happen at the end of a book/sample, with an unsupported layout, or when a dialog interrupts Books.

See [validation notes](docs/VALIDATION.md) for what has and has not been tested.

## Project files

- `Source/BooksReader.swift` — application and self-tests.
- `Source/Info.plist` — portable app bundle metadata.
- `Source/build.command` — local build and test script.
- `docs/VALIDATION.md` — test coverage and known gaps.
- `dist/` — generated app, ignored by Git.

MIT licensed. Copyright © 2026 dudesampson.
