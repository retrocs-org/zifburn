"""Validate PHP pages and download logic without making external requests."""
from html.parser import HTMLParser
from pathlib import Path
import os
import shutil
import subprocess
from urllib.parse import urlsplit, unquote

root = Path(__file__).resolve().parents[1] / 'public-web'
class Check(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.ids = [], set()
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, 'Duplicate ID'
            self.ids.add(attrs['id'])
        if tag == 'img':
            assert 'alt' in attrs, 'Missing image alternative text'
        self.links.extend(attrs[k] for k in ('src', 'href') if k in attrs)

php = os.environ.get('PHP', 'php')
if not shutil.which(php):
    raise SystemExit('PHP is required for website checks.')
for source in sorted(root.glob('*.php')):
    subprocess.run([php, '-l', str(source)], check=True, capture_output=True, text=True)
parsers = {}
for name in ('index.php',):
    render = subprocess.run(
        [php, '-d', 'display_errors=stderr', '-d', 'error_reporting=-1', str(root / name)],
        check=True, capture_output=True, text=True,
        env=dict(os.environ, ZIFBURN_RELEASE_OFFLINE='1'),
    )
    assert not render.stderr, render.stderr
    assert '<?php' not in render.stdout, 'Unrendered PHP'
    if name == 'index.php':
        assert f"VERSION {(root.parent / 'VERSION').read_text().strip()}" in render.stdout, 'Website version differs'
    parser = Check(); parser.feed(render.stdout); parsers[name] = parser
    assert {'get', 'build', 'support'} <= parser.ids, 'Missing one-page sections'
    assert not {'updates', 'start', 'questions'} & parser.ids, 'Obsolete sections remain'
    assert render.stdout.count('>Build from source.</h2>') == 1, 'Build section must be unique'
    assert 'class="nav-get"' in render.stdout and 'href="#get"' in render.stdout
    assert 'get.php' not in render.stdout, 'Navigation must stay on the one-page site'
for name, parser in parsers.items():
    for link in parser.links:
        url = urlsplit(link)
        if url.scheme or url.netloc:
            assert url.scheme == 'https', f'Unexpected external link: {link}'
            continue
        if url.path:
            target = (root / unquote(url.path)).resolve()
            assert target.is_relative_to(root) and target.is_file(), f'Missing/unsafe local link: {link}'
        if url.fragment:
            page = unquote(url.path) or name
            assert page in parsers and url.fragment in parsers[page].ids, f'Missing section: {link}'
for image in ('hex-buffer.jpg', 'chip-search.jpg', 'adapter-banks.jpg', 'themes.jpg', 'icon.png'):
    data = (root / 'assets' / image).read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n') if image.endswith('.png') else data.startswith(b'\xff\xd8\xff')
tests = root.parent / 'Tests/Website/test_releases.php'
result = subprocess.run([php, '-d', 'display_errors=stderr', '-d', 'error_reporting=-1', str(tests)],
                        check=True, capture_output=True, text=True)
assert not result.stderr, result.stderr
print(result.stdout.strip())
print('PHP pages, version, cross-page links, sections and image assets passed.')
