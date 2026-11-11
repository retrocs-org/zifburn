# Releasing ZIFburn

## Contents and licensing

ZIFburn is distributed under the MIT license in LICENSE. minipro is a separate
project with its own license; it is not bundled. The source archive includes
public-web, real application screenshots, tests and the release scripts.
Support/Examples/demo.bin contains example data for screenshots and buffer exploration.

## Validation

Run `make test`, `make universal`, and `make website-check` using full Xcode.
Check that both arm64 and x86_64 are present with:

```sh
lipo build/ZIFburn.app/Contents/MacOS/ZIFburn -verify_arch arm64
lipo build/ZIFburn.app/Contents/MacOS/ZIFburn -verify_arch x86_64
codesign --verify --deep --strict build/ZIFburn.app
```

Before a public binary release, test on supported Apple silicon and Intel Macs.
Use a spare chip and a connected programmer to check read, blank check,
confirmed write, verify, erase, cancellation and reconnect. Check adapter bank
switching on real hardware if advertising that workflow as hardware-tested.
The automated tests do not establish hardware compatibility.

## Version

Set VERSION and keep the unbundled development fallback in AppModel.swift,
Support/Info.plist and `public-web/content.php` consistent. The bundle build
stamps CFBundleShortVersionString from VERSION. CFBundleVersion should increase
for each published binary build.

## Developer ID distribution

`make app` and `make universal` produce ad-hoc signed builds by default.
Do not describe those as notarized releases.

Install your Developer ID Application certificate in your keychain and store
notarization credentials using `xcrun notarytool store-credentials`. Do not put
credentials in the repository. Then run:

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-keychain-profile' make release
```

`make release` invokes `scripts/release.py build`, which runs the release-tool,
website and Swift checks, wraps `scripts/release.sh` for signing/notarization,
and creates the exact publication inventory in `outputs/artifacts/`. The shell
builder remains usable independently. Complete the hardware checks above before
distributing a binary release.

For unified preparation and GitHub/GitLab publication, follow
[docs/RELEASING.md](docs/RELEASING.md):

```sh
python3 scripts/release.py plan
python3 scripts/release.py build
python3 scripts/release.py check
python3 scripts/release.py prepare
# Review outputs/release/manifest.json before this explicit publication step:
python3 scripts/release.py publish --to gitlab,github --confirm-publish
```

Copy `examples/release-config.json` to
`~/Development/tools/git-release/projects/zifburn.json` and configure the existing
repositories, persistent tool paths and keychain profile. Set credential lookup
references for 1Password or environment variables; never store token values in
configuration or source. See `docs/RELEASING.md` for source-only pushes, custom
tags and the combined release command. Publication requires a clean committed
checkout. Builds and preparation do not publish.

## Website

The PHP website lives in `public-web/` and requires a PHP-capable web host.
Run `make website-check` to lint PHP and validate rendered HTML, then
`make website-package` to create the deployable archive in `build/`. See
`public-web/README.md` for server configuration. GitHub Pages cannot execute PHP.

After uploading a signed and notarized binary release, add its download and
SHA-256 checksum links to the website’s Get started section. Keep screenshot
captions and format support in sync with the app.

## Release checklist

- Run tests, build the universal app and validate website assets.
- Complete the hardware smoke test on the supported Mac architectures.
- Sign, notarize, staple and validate the release app.
- Publish the ZIP, checksum, source archive and release notes.
- Update the website’s version, screenshots and download links.
