#!/usr/bin/env python3
"""Create and validate a signed, notarized drag-to-Applications disk image."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from build_provenance import ROOT, digest, require, run, version


def app_hashes(app):
    require(app.is_dir() and not app.is_symlink(), 'Missing or symlinked app bundle')
    files = {}
    for path in app.rglob('*'):
        require(not path.is_symlink(), 'Unexpected symlink in app bundle')
        if path.is_file() and path.name != '.DS_Store':
            files[str(path.relative_to(app))] = digest(path)
    require('Contents/MacOS/ZIFburn' in files, 'Missing app executable')
    return files


def signature(path, runtime=False):
    run(['codesign', '--verify', '--deep', '--strict', path], capture=True)
    info = subprocess.run(['codesign', '-dv', '--verbose=4', str(path)], check=True, capture_output=True, text=True)
    require('Authority=Developer ID Application:' in info.stderr, 'Developer ID signature is required')
    require(not runtime or '(runtime)' in info.stderr, 'App hardened runtime is required')


def verify_app(app, expected_version):
    app_hashes(app)
    with (app / 'Contents/Info.plist').open('rb') as stream:
        require(plistlib.load(stream).get('CFBundleShortVersionString') == expected_version, 'App version differs from release')
    for arch in ('arm64', 'x86_64'):
        run(['lipo', app / 'Contents/MacOS/ZIFburn', '-verify_arch', arch], capture=True)
    signature(app, runtime=True)
    run(['xcrun', 'stapler', 'validate', app], capture=True)
    run(['spctl', '--assess', '--type', 'execute', app], capture=True)


def verify_dmg(image, app):
    run(['hdiutil', 'verify', image], capture=True)
    signature(image)
    run(['xcrun', 'stapler', 'validate', image], capture=True)
    run(['spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', image], capture=True)
    with tempfile.TemporaryDirectory(prefix='zifburn-dmg-mount-') as temp:
        mount = Path(temp) / 'volume'
        subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount),
                                 '-plist', str(image)], check=True, capture_output=True)
        try:
            require((mount / 'Applications').is_symlink() and (mount / 'Applications').readlink() == Path('/Applications'),
                    'DMG must have an Applications shortcut')
            require(app_hashes(mount / 'ZIFburn.app') == app_hashes(app), 'DMG app differs from the validated app')
        finally:
            run(['hdiutil', 'detach', mount], capture=True)
    return {'signing': 'Developer ID', 'ticket_stapled': True, 'gatekeeper': 'accepted', 'app_matches': True}


def build_dmg(app, image, identity, profile, expected_version):
    require(identity.startswith('Developer ID Application:') and profile, 'Signing identity and notarization profile are required')
    require(not image.exists() and not image.is_symlink(), 'Refusing to overwrite an existing DMG')
    verify_app(app, expected_version)
    before = app_hashes(app)
    image.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='zifburn-dmg-stage-') as temp:
        stage = Path(temp) / 'stage'; stage.mkdir()
        shutil.copytree(app, stage / 'ZIFburn.app')
        (stage / 'Applications').symlink_to('/Applications', target_is_directory=True)
        icon = app / 'Contents/Resources/AppIcon.icns'
        if icon.is_file():
            shutil.copyfile(icon, stage / '.VolumeIcon.icns')
            finder_info = bytearray(32); finder_info[8:10] = (0x0400).to_bytes(2, 'big')
            run(['xattr', '-wx', 'com.apple.FinderInfo', finder_info.hex(), stage])
        raw = Path(temp) / 'uncompressed.dmg'
        run(['hdiutil', 'makehybrid', '-hfs', '-hfs-volume-name', 'ZIFburn ' + expected_version,
             '-hfs-openfolder', stage, '-o', raw, stage])
        run(['hdiutil', 'convert', raw, '-format', 'UDZO', '-o', image])
    run(['codesign', '--force', '--timestamp', '--sign', identity, image])
    run(['xcrun', 'notarytool', 'submit', image, '--keychain-profile', profile, '--wait'])
    run(['xcrun', 'stapler', 'staple', image])
    require(before == app_hashes(app), 'Source app changed during DMG packaging')
    validation = verify_dmg(image, app)
    image.with_name(image.name + '.sha256').write_text(digest(image) + '  ' + image.name + '\n')
    return validation


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/ZIFburn.app')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    import os
    target = args.output or ROOT / 'build/release' / ('ZIFburn-' + version() + '-macOS-universal.dmg')
    build_dmg(args.app.resolve(), target.resolve(), os.environ.get('SIGN_IDENTITY', ''),
              os.environ.get('NOTARY_PROFILE', ''), version())
