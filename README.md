# ZIFburn

A native macOS front-end for [minipro](https://gitlab.com/DavidGriffith/minipro),
for XGecu TL866A/CS, TL866II+, T48, T56 and T76 programmers. Written in Swift
and SwiftUI; all hardware operations run through your installed minipro.

![ZIFburn hex buffer and socket placement](public-web/assets/hex-buffer.jpg)

## Features

- Searchable chip database, favorites and per-chip settings.
- Read, write, verify, blank check and erase, with visible commands and progress.
- Hex/ASCII buffer, checksums, file comparison, search, trim and padding.
- Socket placement diagrams and bank-switched EPROM adapter workflows.
- ROM sets, chip duplication, batch writes, stability reads and 13 themes.

Binary and Intel HEX images open in the buffer. Use direct Write File or
Verify Against File for S-record images. See the app’s Help menu for workflows
and shortcuts. Hardware support depends on your minipro version and programmer.

## Build and run

Requires macOS 14+, Xcode 15+ (Swift 5.9+) and minipro:

```sh
brew install minipro
make app
open build/ZIFburn.app
```

The app is built at `build/ZIFburn.app` and ad-hoc signed for local use.
You can also open `Package.swift` in Xcode.

```sh
make test           # Swift tests; requires full Xcode
make universal      # Apple silicon + Intel app
make release-tests  # Offline release tests; requires Python 3.9+
```

## Website and releases

The PHP website, screenshots and hosting instructions are in
[public-web](public-web/README.md). Preview it with PHP 8.2+:

```sh
make website-preview
make website-check  # Also requires Python 3.9+
```

See [RELEASE.md](RELEASE.md) for signing and hardware checks, and
[docs/RELEASING.md](docs/RELEASING.md) for source pushes, packaging and
GitHub/GitLab releases. Publishing requires a clean committed checkout and
explicit confirmation. Signing credentials and local settings stay outside Git.

## License and credits

[MIT](LICENSE). Independent software; not affiliated with XGecu.
Release helpers adapted from BitSkim retain their [MIT notice](scripts/LICENSE-BitSkim).
Workflow inspiration: [minipro-gui](https://github.com/twelve-chairs/minipro-gui),
[minipro-rs](https://gitlab.com/arcturus8081/minipro-rs) and XGecu’s tools.
