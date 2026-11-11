"""Offline release acceptance tests. Network calls are blocked or mocked."""
import contextlib
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
import build_provenance as provenance
import release
import source_release

VALIDATION = {'signing': 'Developer ID', 'hardened_runtime': True,
              'ticket_stapled': True, 'gatekeeper': 'accepted', 'architectures': ['arm64', 'x86_64']}


class FakeAPI:
    def __init__(self, service, manifest):
        self.service, self.manifest = service, manifest
        self.host = 'api.github.com' if service == 'github' else 'gitlab.test'
        self.calls, self.assets, self.packages = [], {}, {}
        self.release = None
        self.fail_upload = False
        self.wrong_digest = False
        self.base, self.path = release.release_paths(service, manifest)

    def request(self, method, path, body=None, file=None, optional=False, hash_body=False, host=None):
        self.calls.append((method, path, copy.deepcopy(body)))
        if method == 'GET' and path == self.base:
            return {'full_name': 'org/zifburn', 'permissions': {'push': True}} if self.service == 'github' else {
                'path_with_namespace': 'group/subgroup/zifburn', 'permissions': {'project_access': {'access_level': 40}}}
        if method == 'GET' and path == self.path:
            return copy.deepcopy(self.release)
        if '/packages/generic/' in path:
            if method == 'GET':
                return self.packages.get(path)
            if self.fail_upload:
                raise RuntimeError('simulated upload interruption')
            self.packages[path] = release.digest(file)
            return {'message': '201 Created'}
        if method == 'POST' and path == self.base + '/releases':
            self.release = {'id': 7, 'tag_name': body['tag_name'], 'body': body.get('body'),
                            'description': body.get('description'), 'draft': body.get('draft', False),
                            'upload_url': 'https://uploads.github.com' + self.base + '/releases/7/assets{?name,label}',
                            'assets': body.get('assets', {'links': []})}
            return copy.deepcopy(self.release)
        if method == 'GET' and '/assets?per_page=' in path:
            return list(self.assets.values())
        if method == 'POST' and '/assets?name=' in path:
            if self.fail_upload:
                raise RuntimeError('simulated upload interruption')
            name = file.name
            value = {'name': name, 'digest': 'sha256:' + ('0' * 64 if self.wrong_digest else release.digest(file))}
            self.assets[name] = value
            return value
        if method == 'PATCH':
            self.release.update(body)
            return copy.deepcopy(self.release)
        if method == 'POST' and path.endswith('/assets/links'):
            self.release['assets']['links'].append(copy.deepcopy(body))
            return body
        raise AssertionError((method, path))


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ('Sources', 'Tests', 'Support', 'public-web/assets', 'scripts', 'docs'):
            (self.root / folder).mkdir(parents=True)
        for name, data in {'VERSION': '0.1\n', 'Package.swift': '// test fixture', 'Makefile': 'all:\n',
                           'LICENSE': 'MIT fixture', 'Sources/main.swift': '// fixture',
                           'Tests/test.swift': '// fixture', 'Support/Info.plist': 'fixture',
                           '.gitignore': 'build/\noutputs/\nwork/\n__pycache__/\n',
                           'docs/RELEASE-NOTES.md': 'Release notes', 'public-web/index.php': '<?php echo "fixture";',
                           'public-web/content.php': '<?php return [];', 'public-web/style.css': 'body{}',
                           'public-web/assets/test.jpg': 'image fixture'}.items():
            (self.root / name).write_text(data)
        self.config = {'github': 'https://github.com/org/zifburn', 'github_git': 'git@github.com:org/zifburn.git',
                       'gitlab': 'https://gitlab.test/group/subgroup/zifburn',
                       'gitlab_git': 'git@gitlab.test:group/subgroup/zifburn.git', 'notary_profile': 'test', 'env': {}}
        for args in (['git', 'init', '-q'], ['git', 'config', 'user.name', 'Release Test'],
                     ['git', 'config', 'user.email', 'test@example.invalid'], ['git', 'add', '.'],
                     ['git', 'commit', '-qm', 'Fixture']):
            subprocess.run(args, cwd=self.root, check=True, capture_output=True)
        self.addCleanup(patch.stopall)
        patch('release.verify_macos', return_value=VALIDATION).start()
        patch('http.client.HTTPSConnection', side_effect=AssertionError('Real networking is forbidden in tests')).start()
        patch.dict(os.environ, {'GITHUB_TOKEN': 'mock-github-credential', 'GITLAB_TOKEN': 'mock-gitlab-credential'}).start()
        self.make_artifacts()

    def make_artifacts(self):
        app = self.root / 'build/ZIFburn.app/Contents/MacOS'
        app.mkdir(parents=True, exist_ok=True)
        (app / 'ZIFburn').write_bytes(b'executable fixture')
        folder = release.output(self.root)
        folder.mkdir(parents=True, exist_ok=True)
        n = release.names(self.root)
        with ZipFile(folder / n['binary'], 'w') as archive:
            archive.write(app / 'ZIFburn', 'ZIFburn.app/Contents/MacOS/ZIFburn')
        with tarfile.open(folder / n['website'], 'w:gz') as archive:
            for path in sorted((self.root / 'public-web').rglob('*')):
                if path.is_file():
                    archive.add(path, arcname=str(path.relative_to(self.root / 'public-web')), recursive=False)
        record = {'version': '0.1', 'commit': provenance.commit(self.root),
                  'source_sha256': provenance.source_hash(self.root), 'macos': VALIDATION,
                  'artifacts': {n[k]: release.digest(folder / n[k]) for k in ('binary', 'website')}}
        provenance.write_json(folder / n['record'], record)
        source_release.create(folder / n['source'], self.root, (folder / n['record']).read_bytes())
        self.write_sums()

    def write_sums(self):
        folder = release.output(self.root)
        (folder / 'SHA256SUMS').write_text(''.join(release.digest(folder / name) + '  ' + name + '\n'
                                                for name in sorted(release.names(self.root).values())))

    def manifest(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return release.prepare(self.config, self.root / 'docs/RELEASE-NOTES.md', self.root)

    def service_setup(self):
        manifest = self.manifest()
        apis = {s: FakeAPI(s, manifest) for s in release.SERVICES}
        remotes = {}
        def api(host, token, github=False): return apis['github' if github else 'gitlab']
        def remote(url, tag, root): return remotes.get(url)
        def run(args, root, capture=False, env=None):
            if args[:2] == ['git', 'push']:
                remotes[args[3] if args[2] == '--no-follow-tags' else args[2]] = manifest['commit']
                return None
            return provenance.run(args, root, capture, env)
        patch('release.API', side_effect=api).start()
        patch('release.remote_tag', side_effect=remote).start()
        patch('release.run', side_effect=run).start()
        return manifest, apis, remotes

    def test_plan_never_builds_or_uploads(self):
        with patch('release.run') as run, patch('release.API') as api, contextlib.redirect_stdout(io.StringIO()) as out:
            release.main(['plan'])
        run.assert_not_called(); api.assert_not_called()
        self.assertIn('scripts/release.sh', out.getvalue())
        self.assertIn('website-package', out.getvalue())

    def test_valid_inventory_and_matching_source(self):
        self.assertEqual(set(release.check(self.root)), set(release.names(self.root).values()) | {'SHA256SUMS'})

    def test_modified_source_blocks_check(self):
        (self.root / 'Sources/main.swift').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'Source changed'): release.check(self.root)

    def test_changed_binary_blocks_check(self):
        (release.output(self.root) / release.names(self.root)['binary']).write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'changed asset'): release.check(self.root)

    def test_missing_and_unexpected_inventory(self):
        file = release.output(self.root) / 'unexpected'
        file.write_bytes(b'extra')
        with self.assertRaisesRegex(ValueError, 'inventory'): release.inventory(self.root)
        file.unlink()
        (release.output(self.root) / release.names(self.root)['website']).unlink()
        with self.assertRaisesRegex(ValueError, 'inventory'): release.inventory(self.root)

    def test_duplicate_checksum_rejected(self):
        sums = release.output(self.root) / 'SHA256SUMS'
        sums.write_text(sums.read_text() + sums.read_text().splitlines()[0] + '\n')
        with self.assertRaisesRegex(ValueError, 'duplicate'): release.inventory(self.root)

    def test_symlinked_asset_rejected(self):
        file = release.output(self.root) / release.names(self.root)['binary']
        file.unlink(); file.symlink_to(self.root / 'LICENSE')
        with self.assertRaisesRegex(ValueError, 'symlinked'): release.inventory(self.root)

    def test_archive_contents_cannot_be_forged_by_rehashing(self):
        with tarfile.open(release.output(self.root) / release.names(self.root)['source'], 'w:gz'):
            pass
        self.write_sums()
        with self.assertRaisesRegex(ValueError, 'Source archive differs'): release.check(self.root)

    def test_signed_bundle_must_match_zip(self):
        (self.root / 'build/ZIFburn.app/Contents/MacOS/ZIFburn').write_bytes(b'changed bundle')
        with self.assertRaisesRegex(ValueError, 'validated app bundle'): release.check(self.root)

    def test_missing_notarization_blocks_check(self):
        with patch('release.verify_macos', side_effect=ValueError('No notarization')):
            with self.assertRaisesRegex(ValueError, 'notarization'): release.check(self.root)

    def test_extracted_source_can_prepare_but_not_publish(self):
        shutil = __import__('shutil')
        shutil.rmtree(self.root / '.git')
        self.make_artifacts()
        self.assertIsNone(self.manifest()['commit'])
        with self.assertRaisesRegex(ValueError, 'Git checkout'): release.publish(['github'], True, self.root)

    def test_dirty_and_ignored_source_block_publication(self):
        self.manifest()
        (self.root / 'Sources/main.swift').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'Commit all'): release.publish(['github'], True, self.root)
        subprocess.run(['git', 'checkout', '--', 'Sources/main.swift'], cwd=self.root, check=True)
        with (self.root / '.git/info/exclude').open('a') as stream: stream.write('\nSources/ignored.swift\n')
        (self.root / 'Sources/ignored.swift').write_text('hidden')
        with self.assertRaisesRegex(ValueError, 'ignored release input'): provenance.commit(self.root, clean=True)

    def test_untracked_source_blocks_publication(self):
        self.manifest(); (self.root / 'Sources/new.swift').write_text('new')
        with self.assertRaisesRegex(ValueError, 'Commit all'): release.publish(['github'], True, self.root)

    def test_explicit_confirmation_required(self):
        with patch('release.API') as api:
            with self.assertRaisesRegex(ValueError, 'confirm-publish'): release.publish(['github'], False, self.root)
        api.assert_not_called()

    def test_repository_validation(self):
        for url in ['http://github.com/a/b', 'https://user:secret@github.com/a/b',
                    'https://github.com/a/../b', 'https://github.com/a/b?q=x',
                    'https://elsewhere.test/a/b', 'https://github.com/a/b/c']:
            with self.assertRaises(ValueError): release.repository(url, True)
        self.assertEqual(release.repository(self.config['gitlab']), ('gitlab.test', 'group/subgroup/zifburn'))
        bad = dict(self.config, github_git='git@github.com:wrong/project.git')
        with self.assertRaisesRegex(ValueError, 'must match'): release.git_destination(bad, 'github')

    def test_configuration_rejects_tokens(self):
        file = self.root / 'config.json'
        file.write_text(json.dumps({'env': {'GITHUB_TOKEN': 'bad'}}))
        with self.assertRaisesRegex(ValueError, 'Only SIGN_IDENTITY'): release.configuration(file)
        with self.assertRaisesRegex(ValueError, 'credential'): release.secret_check('mock-github-credential')

    def test_source_archive_excludes_local_config_and_caches(self):
        (self.root / 'work').mkdir()
        (self.root / 'work/release-config.json').write_text('local settings')
        path = self.root / 'test.tar.gz'
        source_release.create(path, self.root)
        with tarfile.open(path) as archive:
            self.assertFalse(any('/work/' in n or '/outputs/' in n or '/build/' in n for n in archive.getnames()))

    def test_missing_token_preflights_before_mutation(self):
        _, apis, remotes = self.service_setup()
        with patch.dict(os.environ, {'GITLAB_TOKEN': ''}):
            with self.assertRaisesRegex(ValueError, 'GITLAB_TOKEN'): release.publish(['github', 'gitlab'], True, self.root)
        self.assertFalse(remotes)
        self.assertFalse(any(c[0] != 'GET' for api in apis.values() for c in api.calls))

    def test_conflicting_remote_tag_stops_all_uploads(self):
        manifest, apis, remotes = self.service_setup()
        remotes[manifest['gitlab_git']] = 'f' * 40
        with self.assertRaisesRegex(ValueError, 'conflicting remote tag'): release.publish(['github', 'gitlab'], True, self.root)
        self.assertFalse(any(c[0] != 'GET' for api in apis.values() for c in api.calls))

    def test_annotated_remote_tags_resolve_to_commit(self):
        with patch('release.run', return_value='tagobject\trefs/tags/v0.1\ncommitobject\trefs/tags/v0.1^{}'):
            self.assertEqual(release.remote_tag('https://example.invalid/a/b', 'v0.1', self.root), 'commitobject')

    def test_github_draft_published_only_after_full_hashes(self):
        _, apis, _ = self.service_setup()
        with contextlib.redirect_stdout(io.StringIO()): release.publish(['github'], True, self.root)
        api = apis['github']
        self.assertFalse(api.release['draft'])
        last_upload = max(i for i,c in enumerate(api.calls) if c[0] == 'POST' and '/assets?name=' in c[1])
        patch_index = next(i for i,c in enumerate(api.calls) if c[0] == 'PATCH')
        self.assertGreater(patch_index, last_upload)
        receipt = provenance.read_json(self.root / 'outputs/release/receipt.json')
        self.assertIn('github', receipt['completed'])
        self.assertEqual(provenance.run(['git', 'cat-file', '-t', 'refs/tags/v0.1'], self.root, True), 'tag')

    def test_github_wrong_upload_digest_keeps_draft(self):
        _, apis, _ = self.service_setup(); apis['github'].wrong_digest = True
        with self.assertRaisesRegex(ValueError, 'upload digest differs'): release.publish(['github'], True, self.root)
        self.assertTrue(apis['github'].release['draft'])
        self.assertFalse(any(c[0] == 'PATCH' for c in apis['github'].calls))

    def test_existing_unknown_github_digest_stops(self):
        manifest, apis, _ = self.service_setup(); api = apis['github']
        api.release = {'id':7, 'tag_name':'v0.1','body':manifest['notes'],'draft':True}
        name = next(iter(manifest['files'])); api.assets[name] = {'name':name, 'digest':None}
        with self.assertRaisesRegex(ValueError, 'unknown digest'): release.publish(['github'], True, self.root)
        self.assertFalse(any(c[0] != 'GET' for c in api.calls))

    def test_matching_assets_resume_after_interruption(self):
        manifest, apis, _ = self.service_setup(); api = apis['github']
        api.fail_upload = True
        with self.assertRaises(RuntimeError): release.publish(['github'], True, self.root)
        api.fail_upload = False
        name, sha = next(iter(manifest['files'].items()))
        api.assets[name] = {'name':name,'digest':'sha256:'+sha}
        with contextlib.redirect_stdout(io.StringIO()): release.publish(['github'], True, self.root)
        posted = [c[1] for c in api.calls if c[0] == 'POST' and '/assets?name=' in c[1]]
        self.assertFalse(any(p.endswith('?name='+name) for p in posted[1:]))
        self.assertFalse(api.release['draft'])

    def test_gitlab_download_verification_precedes_release(self):
        manifest, apis, _ = self.service_setup()
        with contextlib.redirect_stdout(io.StringIO()): release.publish(['gitlab'], True, self.root)
        api = apis['gitlab']
        self.assertEqual(len(api.packages), len(manifest['files']))
        created = next(i for i,c in enumerate(api.calls) if c[0]=='POST' and c[1]==api.base+'/releases')
        self.assertTrue(all(i<created for i,c in enumerate(api.calls) if c[0]=='PUT'))
        self.assertEqual(len(api.release['assets']['links']),len(manifest['files']))

    def test_conflicting_gitlab_package_is_not_overwritten(self):
        manifest, apis, _ = self.service_setup(); api = apis['gitlab']
        name = next(iter(manifest['files'])); api.packages[release.package_path(api.base,manifest,name)]='0'*64
        with self.assertRaisesRegex(ValueError, 'package bytes differ'): release.publish(['gitlab'], True, self.root)
        self.assertFalse(any(c[0]=='PUT' for c in api.calls))

    def test_completed_destination_survives_later_failure(self):
        _, apis, _ = self.service_setup(); apis['gitlab'].fail_upload = True
        with self.assertRaises(RuntimeError), contextlib.redirect_stdout(io.StringIO()):
            release.publish(['github','gitlab'], True, self.root)
        receipt = provenance.read_json(self.root/'outputs/release/receipt.json')
        self.assertIn('github',receipt['completed']); self.assertNotIn('gitlab',receipt['completed'])
        self.assertFalse(apis['github'].release['draft'])
        apis['gitlab'].fail_upload = False
        before = len([c for c in apis['github'].calls if c[0]!='GET'])
        with contextlib.redirect_stdout(io.StringIO()): release.publish(['github','gitlab'], True, self.root)
        self.assertEqual(before,len([c for c in apis['github'].calls if c[0]!='GET']))

    def test_receipt_cannot_follow_another_manifest(self):
        manifest, _, _ = self.service_setup()
        path = self.root/'outputs/release/receipt.json'
        provenance.write_json(path, {'manifest_sha256':'0'*64,'completed':{}})
        with self.assertRaisesRegex(ValueError,'different manifest'): release.publish(['github'],True,self.root)
        with self.assertRaisesRegex(ValueError,'Source changed'):
            (self.root/'docs/RELEASE-NOTES.md').write_text('changed')
            release.prepare(self.config,self.root/'docs/RELEASE-NOTES.md',self.root)

    def test_destination_names_are_distinct_and_supported(self):
        for value in ['', 'github,github', 'other', 'github,gitlab,']:
            with self.assertRaises(ValueError): release.destinations(value)

    def test_build_runs_all_targets_before_packaging(self):
        import shutil
        folder = release.output(self.root)
        n = release.names(self.root)
        binary, website = (folder / n['binary']).read_bytes(), (folder / n['website']).read_bytes()
        shutil.rmtree(self.root / 'outputs')
        commands = []
        def fake_run(args, root, capture=False, env=None):
            commands.append(args)
            if args[:2] == ['make', 'website-package']:
                (root / 'build/zifburn-website.tar.gz').write_bytes(website)
            if args == ['bash', 'scripts/release.sh']:
                (root / 'build/release').mkdir(exist_ok=True)
                (root / 'build/release' / n['binary']).write_bytes(binary)
            if args == ['swift', '--version']: return 'Swift test compiler'
        config = dict(self.config, env={'SIGN_IDENTITY':'Developer ID Application: Fixture'})
        with patch('release.run', side_effect=fake_run): release.build(config, self.root)
        self.assertEqual(commands[:3], release.build_commands())
        release.check(self.root)

    def test_source_changes_during_build_block_packaging(self):
        import shutil
        shutil.rmtree(self.root / 'outputs')
        def fake_run(args, root, capture=False, env=None):
            if args[:2] == ['make', 'website-package']:
                (root / 'Sources/main.swift').write_text('changed during build')
        config = dict(self.config, env={'SIGN_IDENTITY':'Developer ID Application: Fixture'})
        with patch('release.run', side_effect=fake_run):
            with self.assertRaisesRegex(ValueError, 'Source changed during build'): release.build(config, self.root)
        self.assertFalse(release.output(self.root).exists())

    def test_source_archive_is_deterministic(self):
        a, b = self.root / 'one.tar.gz', self.root / 'two.tar.gz'
        source_release.create(a, self.root); source_release.create(b, self.root)
        self.assertEqual(a.read_bytes(), b.read_bytes())

    def test_conflicting_notes_fail_before_tag_push(self):
        manifest, apis, remotes = self.service_setup()
        apis['github'].release = {'id':7, 'tag_name':'v0.1','body':'different notes','draft':True}
        with self.assertRaisesRegex(ValueError, 'release notes differ'): release.publish(['github'], True, self.root)
        self.assertFalse(remotes)

    def test_conflicting_gitlab_release_link_is_rejected(self):
        manifest, apis, remotes = self.service_setup(); api = apis['gitlab']
        name = next(iter(manifest['files']))
        api.release = {'tag_name':'v0.1','description':manifest['notes'],
                       'assets':{'links':[{'name':name, 'url':'https://elsewhere.invalid/file'}]}}
        with self.assertRaisesRegex(ValueError, 'link destination differs'): release.publish(['gitlab'], True, self.root)
        self.assertFalse(remotes)

    def test_local_conflicting_tag_does_not_push(self):
        manifest, apis, remotes = self.service_setup()
        provenance.run(['git','tag','-a','v0.1','-m','Fixture'], self.root)
        # A lightweight tag is refused even if its commit matches.
        provenance.run(['git','tag','-d','v0.1'], self.root, True)
        provenance.run(['git','tag','v0.1'], self.root)
        with self.assertRaisesRegex(ValueError, 'must be annotated'): release.publish(['github'], True, self.root)
        self.assertFalse(remotes)

    def test_completed_receipt_cannot_hide_deleted_release(self):
        _, apis, _ = self.service_setup()
        with contextlib.redirect_stdout(io.StringIO()): release.publish(['github'], True, self.root)
        apis['github'].release = None
        with self.assertRaisesRegex(ValueError, 'missing remotely'): release.publish(['github'], True, self.root)

    def test_api_does_not_follow_redirects_or_forward_tokens(self):
        from unittest.mock import Mock
        connection = Mock()
        response = Mock(status=302)
        connection.getresponse.return_value = response
        with patch('http.client.HTTPSConnection', return_value=connection):
            api = release.API('api.github.com', 'test-token', True)
            with self.assertRaisesRegex(ValueError, 'HTTP 302'): api.request('GET', '/repos/org/zifburn')
            with self.assertRaisesRegex(ValueError, 'Unexpected API host'):
                api.request('POST', '/upload', host='evil.invalid')
        self.assertEqual(connection.request.call_count, 1)


    def test_publication_contains_only_binary_and_individual_checksum(self):
        manifest = self.manifest()
        binary = release.names(self.root)['binary']
        self.assertEqual(set(manifest['files']), {binary, binary + '.sha256'})
        self.assertEqual(set(manifest['inventory']), set(release.names(self.root).values()) | {'SHA256SUMS'})
        sidecar = (release.publication_folder(self.root)/(binary+'.sha256')).read_text()
        self.assertEqual(sidecar, release.digest(release.output(self.root)/binary)+'  '+binary+'\n')

    def test_changed_staged_copy_blocks_publish(self):
        manifest, apis, remotes = self.service_setup()
        (release.publication_folder(self.root)/next(iter(manifest['files']))).write_bytes(b'changed stage')
        with self.assertRaisesRegex(ValueError,'Staged publication asset changed'):
            release.publish(['github'],True,self.root)
        self.assertFalse(remotes)
        self.assertFalse(apis['github'].calls)

    def test_custom_tag_and_annotation_are_frozen(self):
        with contextlib.redirect_stdout(io.StringIO()):
            manifest=release.prepare(self.config,self.root/'docs/RELEASE-NOTES.md',self.root,
                                     tag='0.1',tag_message='ZIFburn 0.1 release')
        self.assertEqual(manifest['tag'],'0.1')
        self.assertEqual(manifest['tag_message'],'ZIFburn 0.1 release')
        with self.assertRaisesRegex(ValueError,'Tag differs'):
            release.publish(['github'],True,self.root,tag='other')
        with self.assertRaisesRegex(ValueError,'annotation differs'):
            release.publish(['github'],True,self.root,tag_message='changed')

    def test_invalid_tags_are_refused(self):
        from release_support import release_tag
        for tag in ('', '-option','bad..tag','bad tag','refs/../tag'):
            with self.assertRaises(ValueError): release_tag(tag)

    def test_configured_destinations_must_match_manifest(self):
        manifest, _, remotes = self.service_setup()
        changed=dict(self.config,github='https://github.com/org/other',github_git='git@github.com:org/other.git')
        with self.assertRaisesRegex(ValueError,'Destination changed'):
            release.publish(['github'],True,self.root,config=changed)
        self.assertFalse(remotes)

    def test_persistent_python_is_used_and_api_tokens_not_in_build_environment(self):
        import shutil
        folder=release.output(self.root); n=release.names(self.root)
        binary, website=(folder/n['binary']).read_bytes(),(folder/n['website']).read_bytes()
        shutil.rmtree(self.root/'outputs')
        observed=[]
        config=dict(self.config,env={'SIGN_IDENTITY':'Developer ID Application: Fixture',
                                    'ZIFBURN_RELEASE_PYTHON':'/persistent/python'})
        def fake_run(args,root,capture=False,env=None):
            if env is not None:
                self.assertNotIn('GITHUB_TOKEN',env); self.assertNotIn('GITLAB_TOKEN',env)
                self.assertEqual(env['PYTHON'],'/persistent/python')
                observed.append(args)
            if args[:2]==['make','website-package']:
                (root/'build/zifburn-website.tar.gz').write_bytes(website)
            if args==['bash','scripts/release.sh']:
                (root/'build/release').mkdir(exist_ok=True)
                (root/'build/release'/n['binary']).write_bytes(binary)
            if args==['swift','--version']: return 'Swift fixture'
        with patch('release.run',side_effect=fake_run): release.build(config,self.root)
        self.assertEqual(observed[0][0],'/persistent/python')

    def test_onepassword_credentials_are_captured_without_logging(self):
        import release_support as support
        from types import SimpleNamespace
        config={'credentials':{'github':{'provider':'1password','vault':'Test Vault','item':'github.com','field':'org/zifburn-rw'}}}
        result=SimpleNamespace(returncode=0,stdout=json.dumps({'label':'org/zifburn-rw','value':'opaque-mock-secret'}))
        with patch('release_support.subprocess.run',return_value=result) as command, contextlib.redirect_stdout(io.StringIO()) as out:
            token=support.credential('github',config)
        self.assertEqual(token,'opaque-mock-secret'); self.assertEqual(out.getvalue(),'')
        args=command.call_args.args[0]
        self.assertIn('label=org/zifburn-rw',args)
        self.assertNotIn('opaque-mock-secret',args)

    def test_onepassword_reference_and_failure_do_not_print_secret_output(self):
        import release_support as support
        from types import SimpleNamespace
        config={'credentials':{'gitlab':{'provider':'1password','reference':'op://Vault/Item/Field'}}}
        with patch('release_support.subprocess.run',return_value=SimpleNamespace(returncode=0,stdout='mock-value')) as command:
            self.assertEqual(support.credential('gitlab',config),'mock-value')
            self.assertEqual(command.call_args.args[0],['op','read','--no-newline','op://Vault/Item/Field'])
        with patch('release_support.subprocess.run',return_value=SimpleNamespace(returncode=1,stdout='sensitive stdout',stderr='sensitive stderr')):
            with self.assertRaises(ValueError) as error: support.credential('gitlab',config)
        self.assertNotIn('sensitive',str(error.exception))

    def test_onepassword_ambiguous_fields_are_refused(self):
        import release_support as support
        from types import SimpleNamespace
        config={'credentials':{'github':{'provider':'1password','vault':'V','item':'I','field':'F'}}}
        result=SimpleNamespace(returncode=0,stdout=json.dumps([{'label':'F','value':'a'},{'label':'F','value':'b'}]))
        with patch('release_support.subprocess.run',return_value=result):
            with self.assertRaisesRegex(ValueError,'ambiguous'): support.credential('github',config)

    def test_external_configuration_path_can_be_overridden(self):
        import release_support as support
        with patch.dict(os.environ,{'ZIFBURN_RELEASE_CONFIG':'~/release-settings.json'}):
            self.assertEqual(support.default_config_path(),Path.home()/'release-settings.json')

    def test_source_preflight_does_not_push_or_make_release_assets(self):
        import release_support as support
        calls=[]
        def run(args,root,capture=False,env=None):
            calls.append(args)
            if args[:2]==['git','push']: return ''
            return provenance.run(args,root,capture,env)
        with patch('release_support.run',side_effect=run), contextlib.redirect_stdout(io.StringIO()):
            support.push_source(self.config,['github','gitlab'],release.git_destination,dry_run=True,root=self.root)
        pushes=[a for a in calls if a[:2]==['git','push']]
        self.assertEqual(len(pushes),2)
        self.assertTrue(all('--dry-run' in a and '--no-follow-tags' in a for a in pushes))
        self.assertTrue(all('refs/heads/' in a[-1] and 'refs/tags/' not in a[-1] for a in pushes))

    def test_source_upload_requires_confirmation(self):
        import release_support as support
        with patch('release_support.run') as run:
            with self.assertRaisesRegex(ValueError,'confirm-push'):
                support.push_source(self.config,['github'],release.git_destination,root=self.root)
        run.assert_not_called()

    def test_source_preflights_all_destinations_before_push(self):
        import release_support as support
        calls=[]; revision=provenance.commit(self.root)
        def run(args,root,capture=False,env=None):
            calls.append(args)
            if args[:2]==['git','push']: return ''
            if args[:2]==['git','ls-remote']: return revision+'\trefs/heads/master'
            return provenance.run(args,root,capture,env)
        with patch('release_support.run',side_effect=run), contextlib.redirect_stdout(io.StringIO()):
            support.push_source(self.config,['github','gitlab'],release.git_destination,confirmed=True,root=self.root)
        pushes=[a for a in calls if a[:2]==['git','push']]
        self.assertTrue(all('--dry-run' in a for a in pushes[:2]))
        self.assertTrue(all('--dry-run' not in a for a in pushes[2:]))

    def test_initialization_refuses_remote_history_before_local_mutation(self):
        import release_support as support,shutil
        shutil.rmtree(self.root/'.git')
        with patch('release_support.run',return_value='commit\trefs/heads/main'):
            with self.assertRaisesRegex(ValueError,'Remote already has history'):
                support.initialize_source(self.config,['github'],release.git_destination,self.root)
        self.assertFalse((self.root/'.git').exists())

    def test_initialization_only_commits_allowlisted_source(self):
        import release_support as support,shutil
        shutil.rmtree(self.root/'.git')
        # A foreign local file is not staged, even when it is not ignored.
        (self.root/'unrelated-local.txt').write_text('local file')
        def run(args,root,capture=False,env=None):
            if args[:2]==['git','ls-remote']: return ''
            return provenance.run(args,root,capture,env)
        identity={'GIT_AUTHOR_NAME':'Release Test','GIT_AUTHOR_EMAIL':'test@example.invalid',
                  'GIT_COMMITTER_NAME':'Release Test','GIT_COMMITTER_EMAIL':'test@example.invalid'}
        with patch('release_support.run',side_effect=run),patch.dict(os.environ,identity),contextlib.redirect_stdout(io.StringIO()):
            support.initialize_source(self.config,['github'],release.git_destination,self.root)
        tracked=provenance.run(['git','ls-files'],self.root,True).splitlines()
        self.assertNotIn('unrelated-local.txt',tracked)
        self.assertIn('Sources/main.swift',tracked)


    def test_combined_release_requires_confirmation_before_prepare(self):
        with patch('release.configuration',return_value=self.config),patch('release.prepare') as prepare,patch('release.publish') as publish:
            with self.assertRaisesRegex(ValueError,'confirm-publish'):
                release.main(['release','--config',str(self.root/'VERSION')])
        prepare.assert_not_called();publish.assert_not_called()

    def test_combined_release_validates_destinations_before_prepare(self):
        with patch('release.configuration',return_value=self.config),patch('release.prepare') as prepare:
            with self.assertRaisesRegex(ValueError,'distinct destinations'):
                release.main(['release','--config',str(self.root/'VERSION'),'--to','github,github','--confirm-publish'])
        prepare.assert_not_called()

    def test_combined_release_uses_prepared_tag_and_config(self):
        with patch('release.configuration',return_value=self.config),patch('release.prepare') as prepare,patch('release.publish') as publish:
            release.main(['release','--config',str(self.root/'VERSION'),'--tag','0.1','--tag-message','Release 0.1','--to','github','--confirm-publish'])
        self.assertEqual(prepare.call_args.kwargs,{'tag':'0.1','tag_message':'Release 0.1'})
        self.assertEqual(publish.call_args.args,(['github'],True))
        self.assertEqual(publish.call_args.kwargs,{'config':self.config,'tag':'0.1','tag_message':'Release 0.1'})


if __name__ == '__main__':
    unittest.main()
