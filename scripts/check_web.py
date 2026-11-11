"""Check local website links, assets, fragment targets, and screenshot files."""
from html.parser import HTMLParser
from pathlib import Path
import os
import shutil
import subprocess
import sys
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
    sys.exit('PHP is required for website checks. Install PHP and run make website-check again.')
for source in sorted(root.glob('*.php')):
    subprocess.run([php, '-l', str(source)], check=True, capture_output=True, text=True)
render = subprocess.run(
    [php, '-d', 'display_errors=stderr', '-d', 'error_reporting=-1', str(root / 'index.php')],
    check=True, capture_output=True, text=True,
)
assert not render.stderr, render.stderr
assert '<?php' not in render.stdout, 'Unrendered PHP in page output'
assert f"VERSION {(root.parent / 'VERSION').read_text().strip()}" in render.stdout, 'Website version differs from VERSION'
parser = Check()
parser.feed(render.stdout)
for link in parser.links:
    url = urlsplit(link)
    if url.scheme or url.netloc:
        assert url.scheme == 'https', f'Unexpected external link: {link}'
        continue
    if url.path:
        target = (root / unquote(url.path)).resolve()
        assert target.is_relative_to(root), f'Link escapes website: {link}'
        assert target.is_file(), f'Missing local asset: {link}'
    elif url.fragment:
        assert url.fragment in parser.ids, f'Missing section: {link}'
for image in ('hex-buffer.jpg', 'chip-search.jpg', 'adapter-banks.jpg', 'themes.jpg', 'icon.png'):
    data = (root / 'assets' / image).read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n') if image.endswith('.png') else data.startswith(b'\xff\xd8\xff')
print('PHP syntax, page rendering, version, links, sections and image assets passed.')
