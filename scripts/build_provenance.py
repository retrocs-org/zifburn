"""Source selection and release provenance shared by packaging and publication."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOTS = ('VERSION', 'Package.swift', 'Makefile', '.gitignore', 'LICENSE',
                'README.md', 'RELEASE.md', 'Sources', 'Tests', 'Support', 'public-web',
                'scripts', 'examples', 'docs', '.github')
REQUIRED = ('VERSION', 'Package.swift', 'Makefile', 'LICENSE', 'Sources', 'Tests',
            'Support', 'public-web', 'scripts')


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(args, root=ROOT, capture=False, env=None):
    result = subprocess.run([str(a) for a in args], cwd=root, env=env, check=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None, text=True)
    return result.stdout.strip() if capture else None


def version(root=ROOT):
    value = (root / 'VERSION').read_text().strip()
    require(re.fullmatch(r'\d+\.\d+(?:\.\d+)?', value), 'Invalid VERSION')
    return value


def digest(path):
    require(path.is_file() and not path.is_symlink(), 'Missing or symlinked file: ' + path.name)
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def source_files(root=ROOT):
    for name in REQUIRED:
        require((root / name).exists(), 'Missing source input: ' + name)
    paths = []
    for name in SOURCE_ROOTS:
        base = root / name
        require(not base.is_symlink(), 'Symlinked source root: ' + name)
        for path in sorted(base.rglob('*')) if base.is_dir() else [base]:
            rel = path.relative_to(root)
            if '__pycache__' in rel.parts or path.name == '.DS_Store' or path.name.startswith('._'):
                continue
            require(not path.is_symlink(), 'Symlinked source input: ' + str(rel))
            if path.is_file():
                paths.append(path)
    return sorted(paths)


def source_hash(root=ROOT):
    h = hashlib.sha256()
    for path in source_files(root):
        h.update(str(path.relative_to(root)).encode() + b'\0' + digest(path).encode() + b'\n')
    return h.hexdigest()


def commit(root=ROOT, clean=False):
    try:
        top = run(['git', 'rev-parse', '--show-toplevel'], root, True)
    except subprocess.CalledProcessError:
        if not clean:
            return None
        raise ValueError('Publication requires a committed Git checkout') from None
    require(Path(top).samefile(root), 'Project root must be the Git checkout root')
    if clean:
        require(not run(['git', 'status', '--porcelain', '--untracked-files=all'], root, True),
                'Commit all release inputs before publication')
        tracked = set(run(['git', 'ls-files', '-z'], root, True).split('\0'))
        for path in source_files(root):
            require(str(path.relative_to(root)) in tracked,
                    'Untracked or ignored release input: ' + str(path.relative_to(root)))
    return run(['git', 'rev-parse', 'HEAD'], root, True)


def write_json(path, value):
    require(not path.is_symlink() and not path.parent.is_symlink(), 'Symlinked record path')
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    require(not temp.is_symlink(), 'Symlinked temporary record')
    temp.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    temp.replace(path)


def read_json(path):
    require(path.is_file() and not path.is_symlink(), 'Missing or symlinked record: ' + path.name)
    return json.loads(path.read_text())
