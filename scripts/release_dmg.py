"""Append a verified disk image to an existing release without changing its tag."""
from pathlib import Path
from urllib.parse import quote, urlsplit
from zipfile import ZipFile
from build_provenance import ROOT, digest, require, run, read_json, write_json
from dmg_release import build_dmg, verify_app, verify_dmg


def extend_release(config, tag, services, confirmed=False, root=ROOT):
    import release as r
    require(tag and all(c.isalnum() or c in '.-_' for c in tag), 'Invalid existing release tag')
    revision = run(['git', 'rev-parse', 'refs/tags/' + tag + '^{commit}'], root, True)
    v = run(['git', 'show', 'refs/tags/' + tag + ':VERSION'], root, True).strip()
    require(v and all(c.isdigit() or c == '.' for c in v), 'Invalid tagged version')
    manifest = dict(config, tag=tag, version=v)
    zipname = 'ZIFburn-' + v + '-macOS-universal.zip'
    image_name = 'ZIFburn-' + v + '-macOS-universal.dmg'
    apis, ziphashes = {}, []
    for service in services:
        host, _ = r.repository(config[service], service == 'github')
        api = r.API('api.github.com' if service == 'github' else host, r.credential(service, config), service == 'github')
        require(r.remote_tag(r.git_destination(config, service), tag, root) == revision, service + ': tag differs')
        base, path = r.release_paths(service, manifest)
        state = api.request('GET', path)
        require(state.get('tag_name') == tag and not state.get('draft'), 'Existing published release is required')
        if service == 'github':
            assets = r.github_assets(api, base, state)
            sha = assets.get(zipname, {}).get('digest', '')
            require(sha.startswith('sha256:') and len(sha) == 71, 'Published ZIP must have a SHA256 digest')
            ziphashes.append(sha[7:])
        else:
            ziphashes.append(api.request('GET', r.package_path(base, manifest, zipname), hash_body=True))
        apis[service] = api
    require(len(set(ziphashes)) == 1, 'Published ZIP files differ across destinations')
    archive = root / 'outputs/artifacts' / zipname
    require(digest(archive) == ziphashes[0], 'Local ZIP differs from the published release; restore the published ZIP first')
    folder = root / 'outputs' / ('dmg-' + tag)
    require(not folder.is_symlink() and not folder.parent.is_symlink(), 'Symlinked DMG output directory')
    folder.mkdir(parents=True, exist_ok=True)
    app = folder / 'ZIFburn.app'
    if not app.exists():
        with ZipFile(archive) as z:
            for item in z.infolist():
                require(not item.filename.startswith('/') and '..' not in Path(item.filename).parts,
                        'Unsafe ZIP entry')
                require((item.external_attr >> 16) & 0o170000 != 0o120000, 'Unexpected ZIP symlink')
        run(['ditto', '-x', '-k', archive, folder], root)
    verify_app(app, v)
    # Verify the extracted bundle still contains exactly the published ZIP bytes.
    from dmg_release import app_hashes
    import hashlib
    with ZipFile(archive) as z:
        expected = {i.filename[len('ZIFburn.app/'):]: hashlib.sha256(z.read(i)).hexdigest()
                    for i in z.infolist() if i.filename.startswith('ZIFburn.app/') and not i.is_dir()
                    and not i.filename.endswith('/.DS_Store')}
    require(app_hashes(app) == expected, 'Extracted app differs from published ZIP')
    image = folder / image_name
    record = folder / 'manifest.json'
    if image.exists():
        require(record.is_file(), 'Existing DMG lacks a verified manifest; retain it separately before retrying')
        old = read_json(record)
        require(old.get('commit') == revision and old.get('zip_sha256') == ziphashes[0], 'DMG provenance differs')
        require(old.get('files', {}).get(image_name) == digest(image), 'DMG changed since preparation')
        validation = verify_dmg(image, app)
    else:
        validation = build_dmg(app, image, config['env'].get('SIGN_IDENTITY', ''), config['notary_profile'], v)
    sidecar = image.with_name(image.name + '.sha256')
    require(not sidecar.is_symlink(), 'Symlinked checksum file')
    sidecar.write_text(digest(image) + '  ' + image.name + '\n')
    files = {p.name: digest(p) for p in (image, sidecar)}
    evidence = {'tag': tag, 'commit': revision, 'zip_sha256': ziphashes[0], 'files': files, 'validation': validation,
                'destinations': {s: config[s] for s in services}}
    write_json(record, evidence)
    # All destinations are checked for conflicts before any upload.
    def inspect(service):
        api = apis[service]; base, path = r.release_paths(service, manifest)
        state = api.request('GET', path)
        require(state.get('tag_name') == tag and not state.get('draft'), 'Release state changed')
        if service == 'github':
            assets = r.github_assets(api, base, state)
            for name, sha in files.items():
                require(name not in assets or assets[name].get('digest') == 'sha256:' + sha, 'Conflicting GitHub DMG asset')
        else:
            links = state.get('assets', {}).get('links', [])
            for name, sha in files.items():
                package = r.package_path(base, manifest, name)
                current = api.request('GET', package, optional=True, hash_body=True)
                require(current is None or current == sha, 'Conflicting GitLab DMG package')
                matching = [x for x in links if x['name'] == name]
                require(len(matching) <= 1 and all(x['url'] == 'https://' + api.host + package for x in matching), 'Conflicting GitLab DMG link')
        return state
    for service in services:
        inspect(service)
    print('Signed and notarized DMG prepared: ' + str(image))
    if not confirmed:
        print('Add --confirm-publish to append these assets to the existing releases.')
        return
    receipt = {'manifest_sha256': digest(record), 'completed': {}}
    for service in services:
        api = apis[service]; state = inspect(service)
        base, path = r.release_paths(service, manifest)
        require(r.remote_tag(r.git_destination(config, service), tag, root) == revision, 'Remote tag changed')
        assets = r.github_assets(api, base, state) if service == 'github' else {}
        for name, sha in files.items():
            file = folder / name
            require(digest(file) == sha, 'Prepared asset changed')
            if service == 'github':
                upload = urlsplit(state['upload_url'].split('{')[0])
                require(upload.scheme == 'https' and upload.netloc == 'uploads.github.com' and upload.path == base + '/releases/' + str(state['id']) + '/assets', 'Unexpected upload URL')
                if name not in assets:
                    item = api.request('POST', upload.path + '?name=' + quote(name, safe=''), file=file, host=upload.hostname)
                    require(item.get('digest') == 'sha256:' + sha, 'Uploaded GitHub digest differs')
            else:
                package = r.package_path(base, manifest, name)
                if api.request('GET', package, optional=True, hash_body=True) is None:
                    api.request('PUT', package, file=file)
                require(api.request('GET', package, hash_body=True) == sha, 'Uploaded GitLab digest differs')
                if not any(x['name'] == name for x in state.get('assets', {}).get('links', [])):
                    api.request('POST', path + '/assets/links', {'name': name, 'url': 'https://' + api.host + package, 'link_type': 'package'})
        final = inspect(service)
        actual = r.github_assets(api, base, final) if service == 'github' else {x['name']: x for x in final['assets']['links']}
        require(set(files) <= set(actual), 'New release assets are missing')
        receipt['completed'][service] = config[service]
        write_json(folder / 'receipt.json', receipt)
        print(service + ': DMG and checksum uploaded and verified')
