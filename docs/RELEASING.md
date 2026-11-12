# Unified releases

ZIFburn adapts BitSkim’s release workflow for a macOS universal application.
Run `python3 scripts/release.py` from the source folder. Python 3.9+, full Xcode,
PHP, a Developer ID Application identity and a stored notarization profile are
required to build a public release. GitHub and GitLab are the only publication
destinations.

## External settings

The default settings file is:

```text
~/Development/tools/git-release/projects/zifburn.json
```

Copy `examples/release-config.json` there and replace the placeholders. Keep
actual repository destinations, machine paths and credential references outside
the public checkout. Override the location with `--config /path/to/settings.json`
or the `ZIFBURN_RELEASE_CONFIG` environment variable. The configuration supports
GitLab nested groups and a matching HTTPS or ordinary SSH Git destination.

The allowed build settings in `env` are `SIGN_IDENTITY`, `PHP` and
`ZIFBURN_RELEASE_PYTHON`. The latter selects a persistent Python executable for
release-tool tests and packaging. `PHP` selects the PHP executable for website
checks. `notary_profile` names an existing notarization keychain profile; a
profile can be shared by several applications using the same Apple account.
Keys and passwords stay in the keychain. The `work/` directory remains ignored
and excluded from archives if used for an explicit alternate settings file.

## Credentials

API credentials are read only during publication. Configure either environment
variables or 1Password references:

```json
"credentials": {
  "github": {"provider": "env", "variable": "GITHUB_TOKEN"},
  "gitlab": {
    "provider": "1password",
    "vault": "YourVault",
    "item": "Your GitLab server item",
    "field": "your-group/zifburn-rw",
    "account": ""
  }
}
```

For an exact copied secret reference, use:

```json
"github": {
  "provider": "1password",
  "reference": "op://YourVault/YourItem/YourField",
  "account": ""
}
```

Use either `reference` or `vault`/`item`/`field`. The named-field form supports
labels containing slashes. Optional `account` selects the intended 1Password
account. The `op` CLI must be installed and connected to the desktop app or
signed in. Missing, ambiguous or cancelled lookups stop publication without
printing secret output. Configuring a reference does not create its token field.

GitHub needs repository Contents write access. GitLab needs API access and at
least Developer project permissions; protected tags and project policies may
require higher access. Git pushes use your ordinary SSH key or Git credential
helper independently of the API token. For GitHub App installation tokens,
repository access is checked through the installation’s repository listing;
user-style `permissions.push` flags are not used as App permission evidence.
This read-only check does not prove Contents write permission. GitHub enforces
that permission when creating a release or uploading an asset, and denied
operations stop without automatic retry.

Never put literal tokens into configuration, source, command-line arguments,
notes or archives. Environment tokens can be supplied by CI secret injection or
an interactive hidden Bash prompt. Build subprocesses have the configured API
token environment variables removed and never call 1Password. The script checks
for known in-memory tokens in metadata; this is not comprehensive secret
scanning of Git history or every possible source input.

## Push source without building

```sh
python3 scripts/release.py source --to gitlab,github --dry-run
python3 scripts/release.py source --to gitlab,github --confirm-push
```

Source pushes require a clean committed checkout. Every selected destination
is dry-run before the first real push. Only the current branch is pushed;
force, mirror and follow-tags are not used. `source_branch` can select a different
destination branch; an empty value keeps the current branch name.

For an extracted folder with no Git history, explicitly initialize it:

```sh
python3 scripts/release.py source --init --to gitlab,github --dry-run
```

`--init` first checks that all selected remotes are accessible and empty. It
requires a reviewed `.gitignore` and Git author identity, initializes a main
branch, stages only allowlisted project inputs, and creates the first local
commit. This changes local Git metadata even with `--dry-run`, but uploads
nothing. Unrelated untracked files remain uncommitted and block the subsequent
clean-checkout preflight until reviewed. Existing committed repositories get no
extra initial commit. Nonempty remotes must be cloned so their history is
preserved. Use `--commit-message` with `source --init` to customize the first
commit message. Source pushes do not build, create releases, or deploy the site.

## Build and check

```sh
python3 scripts/release.py plan
python3 scripts/release.py build
python3 scripts/release.py check
```

`plan` prints commands without building, reading credentials or contacting
services. `build` runs offline release tests, PHP checks/packaging, Swift tests,
the universal build, Developer ID signing, notarization, stapling and Gatekeeper
assessment. It records source fingerprints before and after the build and
packages the validated app, source and website. The underlying
`scripts/release.sh` remains usable independently.

`check` verifies the exact inventory, hashes, source commit/fingerprint,
archive contents, signed app/ZIP agreement, architectures, hardened runtime,
stapled ticket and Gatekeeper assessment. Build records identify compiler,
commit and source inputs. Hardware smoke tests remain separate; follow
`RELEASE.md` before releasing. Dependency downloads and Apple notarization can
use the network, but build/check do not publish repository releases.

Finish source, documentation and website edits before committing and building.
Changed inputs or a different source commit require a new build. An extracted
archive can build, check and prepare; publication requires a committed checkout.

## Prepare and publish

```sh
python3 scripts/release.py prepare --tag 0.1 --tag-message "ZIFburn 0.1 release"
# Review outputs/release/manifest.json and the staged assets.
python3 scripts/release.py publish --tag 0.1 --to gitlab,github --confirm-publish
```

Or prepare and publish a verified build in one explicitly confirmed operation:

```sh
python3 scripts/release.py release --tag 0.1 --to gitlab,github --confirm-publish
```

Omitting `--tag` defaults to `v<version>` from `VERSION`. An explicit tag is used
exactly as supplied, including the release title. `--tag-message` sets the
annotated tag’s text and is frozen in the prepared manifest. Neither setting
changes the application version or rewrites a source commit. Existing tags are
never force-moved.

The manifest records notes, destinations, exact commit and source fingerprint,
full local artifact inventory, and staged upload hashes. Publish rechecks the
current external settings against its frozen destinations and refuses changes.
API credential references may be updated without changing release content.
Use `--notes /path/to/notes.md` to select release notes, or edit
`docs/RELEASE-NOTES.md` before building.

All selected services are preflighted before any tag push or asset upload.
Conflicting tags, notes, unknown GitHub digests, changed assets and mismatched
GitLab package links stop the run. GitHub begins as a draft until the exact
expected hashes are verified. GitLab package uploads are downloaded and hashed
before release links are created. Matching files are reused during retries.
The APIs use HTTPS without credential redirects; installations requiring
object-storage download redirects need a specifically designed adapter.

## Local inventory and publication assets

`outputs/artifacts/` contains:

- `ZIFburn-<version>-macOS-universal.dmg`
- `ZIFburn-<version>-macOS-universal.zip`
- `zifburn-<version>-source.tar.gz`
- `zifburn-<version>-website.tar.gz`
- `BUILD-PROVENANCE.json`
- `SHA256SUMS`

Preparation copies the DMG and ZIP into `outputs/release/publish/` and creates
an individual `.sha256` file for each. These four files are uploaded by default. GitHub
and GitLab supply source downloads from the tagged commit. The standalone source
archive, PHP website package, provenance and aggregate checksum inventory remain
local build/validation artifacts. Publication does not deploy the PHP site.
The app and website packages include their license; adapted release helpers
carry BitSkim’s MIT notice in `scripts/LICENSE-BitSkim`.

Staged copies are bound to the manifest and checked again before each upload.
The explicit source allowlist excludes settings, caches and unrelated local
files. Source archives embed the matching build record; standalone `make dist`
uses the same allowlist without claiming a notarized build record. These checks
establish matching source and artifacts, not bit-for-bit reproducible Apple
signatures or hardware compatibility.

## Failures and resuming

Keep `outputs/release/receipt.json`, manifest and artifacts together. The receipt
binds completed destinations and the current operation to the manifest hash.
Resume the same publish command with the same manifest after reviewing the
failure. Matching remote assets are reused; completed destinations are
revalidated and left intact. A different manifest cannot reuse the receipt.

There is no automatic network retry or cross-service rollback. Run one publisher
per version. Preserve old release evidence outside `outputs/` before beginning a
new release; rebuilding refuses existing artifacts or a publication receipt.
Do not delete a receipt to bypass an interrupted operation.

## Offline tests

```sh
make release-tests
```

Tests use temporary Git repositories, fake binaries and mocked APIs. They cover
credential lookup, token isolation from builds, source-only push preflight,
custom tags, staging, checksums/provenance, conflicts and resumed publication.
Real HTTP calls are blocked. Exercise actual publication against dedicated test
repositories before production tags. No ordinary test publishes real releases.

## API references

- [GitHub release assets](https://docs.github.com/en/rest/releases/assets)
- [GitHub releases](https://docs.github.com/en/rest/releases/releases)
- [GitLab generic packages](https://docs.gitlab.com/user/packages/generic_packages/)
- [GitLab releases](https://docs.gitlab.com/api/releases/)

## Disk images

The build creates a universal ZIP and a drag-to-Applications DMG. Both the app and disk image are Developer ID signed, notarized and stapled. Publication includes both downloads and individual SHA256 checksum files. DMG verification mounts the image read-only and compares its app against the validated build.

To add a DMG to an existing published release without changing its tag or ZIP:

```sh
python3 scripts/release.py add-dmg --tag 0.1 --to gitlab,github --confirm-publish
```

This uses the local `outputs/artifacts` ZIP only after comparing its hash with the published ZIP on every destination. It preserves release notes and existing assets, refuses conflicting DMG files, and records verification evidence under `outputs/dmg-<tag>/`. Omit `--confirm-publish` to prepare and verify without uploading. Keep the manifest and image together for retries.
