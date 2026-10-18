#!/bin/zsh
set -euo pipefail
reader_root="${0:A:h:h}"
reader_build_dir=$(mktemp -d "${TMPDIR:-/tmp/}books-reader-build.XXXXXX")
trap 'rm -rf "$reader_build_dir"' EXIT
reader_app="$reader_root/dist/Books Reader.app"

# Only the generated dist app is replaced; a separately installed app is untouched.
print "Quit any Books Reader app launched from dist before rebuilding."
/usr/bin/xcrun swiftc -target "$(/usr/bin/uname -m)-apple-macos13.0" \
    -module-cache-path "$reader_build_dir/modules" \
    "$reader_root/Source/BooksReader.swift" -o "$reader_build_dir/BooksReader"
"$reader_build_dir/BooksReader" --self-test
/usr/bin/plutil -lint "$reader_root/Source/Info.plist"
/bin/mkdir -p "$reader_app/Contents/MacOS"
/usr/bin/install -m 755 "$reader_build_dir/BooksReader" "$reader_app/Contents/MacOS/BooksReader"
/usr/bin/install -m 644 "$reader_root/Source/Info.plist" "$reader_app/Contents/Info.plist"
print "Built: $reader_app"
print "Move the app to a stable location, open it, and enable Accessibility when prompted."
print "Rebuilding may require removing and re-adding its Accessibility entry."
