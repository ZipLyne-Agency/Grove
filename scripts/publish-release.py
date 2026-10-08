#!/usr/bin/env python3
"""Prepare a signed GitHub update release; publish only with --publish."""
import argparse
import hashlib
import json
import os
import re
import zipfile
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
REPO = 'ZipLyne-Agency/grove'
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def run(*args, capture=False):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, check=True, timeout=180,
                            stdout=subprocess.PIPE if capture else None, text=True)
    return result.stdout.strip() if capture else None


def digest(path):
    return hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--notes', type=Path, required=True)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    archive = args.archive.expanduser().resolve(strict=True)
    config = json.loads((ROOT / 'release/version.json').read_text())
    version, build = config['version'], config['build']
    tag = 'v' + version
    if archive.name != f'Grove-{version}-macOS.zip':
        raise SystemExit('Archive filename must match release/version.json.')
    if run('git', 'status', '--porcelain', capture=True):
        raise SystemExit('Commit and push the reviewed source before preparing a release.')
    run('git', 'fetch', 'origin', 'main')
    head = run('git', 'rev-parse', 'HEAD', capture=True)
    if run('git', 'branch', '--show-current', capture=True) != 'main' or head != run('git', 'rev-parse', 'origin/main', capture=True):
        raise SystemExit('Release source must be the pushed main branch.')
    remote_tags = run('git', 'ls-remote', '--tags', 'origin', f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}', capture=True)
    if remote_tags:
        refs = dict(line.split()[::-1] for line in remote_tags.splitlines())
        target = refs.get(f'refs/tags/{tag}^{{}}', refs.get(f'refs/tags/{tag}'))
        if target != head:
            raise SystemExit('Existing release tag points to a different commit.')
    with zipfile.ZipFile(archive) as contents:
        for name in contents.namelist():
            path = Path(name)
            if path.is_absolute() or '..' in path.parts or path.parts[0] not in ('Grove.app', '__MACOSX'):
                raise SystemExit('Release ZIP contains an unexpected path.')
            if path.parts[0] == '__MACOSX' and len(path.parts) > 1 and path.parts[1] not in ('Grove.app', '._Grove.app'):
                raise SystemExit('Release ZIP contains unexpected metadata.')
    team = os.environ.get('GROVE_TEAM_ID', '')
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise SystemExit('Set GROVE_TEAM_ID to the expected Developer ID team.')
    # Inspect the exact archive, rather than a nearby build that might differ.
    with tempfile.TemporaryDirectory(prefix='grove-release-', dir=archive.parent) as folder:
        stage = Path(folder)
        run('ditto', '-x', '-k', archive, stage)
        app = stage / 'Grove.app'
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        expected_feed = f'https://github.com/{REPO}/releases/latest/download/appcast.xml'
        expected_key = (ROOT / 'release/sparkle-public-key.txt').read_text().strip()
        for key, expected in {'CFBundleShortVersionString': version, 'CFBundleVersion': build,
                              'SUPublicEDKey': expected_key, 'SUFeedURL': expected_feed,
                              'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True}.items():
            if info.get(key) != expected:
                raise SystemExit(f'Archive has unexpected {key}.')
        run('codesign', '--verify', '--deep', '--strict', '-R',
            f'=anchor apple generic and certificate leaf[subject.OU] = \"{team}\"', app)
        run('xcrun', 'stapler', 'validate', app)
        run('spctl', '--assess', '--type', 'execute', app)
    tools = ROOT / '.build/artifacts/sparkle/Sparkle/bin'
    feed = archive.parent / 'appcast.xml'
    if not feed.exists():
        with tempfile.TemporaryDirectory(prefix='grove-feed-', dir=archive.parent) as folder:
            stage = Path(folder)
            shutil.copy2(archive, stage / archive.name)
            run(tools / 'generate_appcast', '--account', 'agency.ziplyne.grove.updates',
                '--download-url-prefix', f'https://github.com/{REPO}/releases/download/{tag}/',
                '--maximum-deltas', '0', '--versions', build, stage)
            shutil.copy2(stage / 'appcast.xml', feed)
    run(tools / 'sign_update', '--verify', '--account', 'agency.ziplyne.grove.updates', feed)
    tree = ET.parse(feed)
    item = tree.find('./channel/item')
    if item is None or item.findtext(SPARKLE + 'version') != build or item.findtext(SPARKLE + 'shortVersionString') != version:
        raise SystemExit('The feed version does not match this release.')
    enclosure = item.find('enclosure')
    if enclosure is None or enclosure.get('url') != f'https://github.com/{REPO}/releases/download/{tag}/{archive.name}' or not enclosure.get(SPARKLE + 'edSignature'):
        raise SystemExit('The signed feed does not point to the immutable release archive.')
    # Verify using the release signing identity from Keychain.
    run(tools / 'sign_update', '--verify', archive, enclosure.get(SPARKLE + 'edSignature'), '--account', 'agency.ziplyne.grove.updates')
    existing = subprocess.run(['gh', 'release', 'view', tag, '--repo', REPO, '--json', 'isDraft,targetCommitish'],
                              capture_output=True, text=True, timeout=60)
    if existing.returncode == 0:
        release = json.loads(existing.stdout)
        if release['targetCommitish'] != head:
            raise SystemExit('Existing draft targets different source. Review it and update its target before publishing.')
        if not release['isDraft']:
            raise SystemExit('This release is already published; published assets are immutable.')
    elif 'release not found' in existing.stderr.lower() or 'not found' in existing.stderr.lower():
        run('gh', 'release', 'create', tag, '--repo', REPO, '--target', head, '--draft',
            '--title', 'Grove ' + version, '--notes-file', args.notes, archive, feed)
    else:
        raise SystemExit('Could not inspect the existing release. Check GitHub authentication and retry.')
    assets = json.loads(run('gh', 'release', 'view', tag, '--repo', REPO, '--json', 'assets', capture=True))['assets']
    if {asset['name'] for asset in assets} != {archive.name, feed.name}:
        raise SystemExit('Draft release contains unexpected assets. Review them before publication.')
    with tempfile.TemporaryDirectory(prefix='grove-draft-check-', dir=archive.parent) as folder:
        run('gh', 'release', 'download', tag, '--repo', REPO, '--dir', folder,
            '--pattern', archive.name, '--pattern', feed.name)
        for path in (archive, feed):
            if digest(Path(folder) / path.name) != digest(path):
                raise SystemExit(f'Draft {path.name} differs from the verified artifact. Refusing publication.')
    if not args.publish:
        print(f'Draft {tag} prepared. Review it before publishing.')
        return
    run('gh', 'release', 'edit', tag, '--repo', REPO, '--draft=false', '--latest')
    for path in (archive, feed):
        url = f'https://github.com/{REPO}/releases/download/{tag}/{path.name}'
        with urllib.request.urlopen(url, timeout=60) as response:
            downloaded = hashlib.sha256(response.read()).hexdigest()
        if downloaded != digest(path):
            raise SystemExit(f'Published {path.name} differs from the verified artifact.')
    with urllib.request.urlopen(expected_feed, timeout=60) as response:
        if hashlib.sha256(response.read()).hexdigest() != digest(feed):
            raise SystemExit('The latest update feed differs from this release.')
    print(f'Published and verified https://github.com/{REPO}/releases/tag/{tag}')


if __name__ == '__main__':
    main()
