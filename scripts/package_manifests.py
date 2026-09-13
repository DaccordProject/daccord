#!/usr/bin/env python3
"""Render review-only package manifests from one stable GitHub release.

Offline and standard-library-only. Release asset digests and SHA256SUMS.txt
must agree; optional locally downloaded assets are also hashed. No submission,
installer execution, source checkout, or catalog credentials are involved.
"""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / 'dist/packaging/templates'
REPOSITORY = 'https://github.com/DaccordProject/daccord'
ASSETS = {
    'WINDOWS_INSTALLER': 'daccord-windows-x86_64-setup.exe',
    'WINDOWS_PORTABLE': 'daccord-windows-x86_64.zip',
    'LINUX': 'daccord-linux-x86_64.tgz',
}
MACOS_ASSETS = ('daccord-macos-universal.dmg', 'daccord-macos-universal-package-manager.dmg')
TOKEN = re.compile(r'@@([A-Z][A-Z0-9_]*)@@')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def checksums_from(data):
    result = {}
    for line in data.decode('utf-8').splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r'([a-fA-F0-9]{64})[ \t]+\*?([A-Za-z0-9][A-Za-z0-9._-]*)', line)
        if match is None:
            raise ValueError('Malformed SHA256SUMS.txt line')
        digest, name = match.groups()
        if name in result:
            raise ValueError(f'Duplicate checksum: {name}')
        result[name] = digest.lower()
    return result


def release_values(release, checksum_data, macos_asset=MACOS_ASSETS[0], assets_dir=None):
    tag = release.get('tag_name', '')
    if not isinstance(tag, str) or re.fullmatch(r'v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', tag) is None:
        raise ValueError('Expected a stable vMAJOR.MINOR.PATCH release tag')
    if release.get('draft') or release.get('prerelease'):
        raise ValueError('Draft and prerelease manifests are not supported')
    if macos_asset not in MACOS_ASSETS:
        raise ValueError('Unsupported macOS asset name')
    published_at = release.get('published_at')
    if not isinstance(published_at, str):
        raise ValueError('Release metadata must include published_at')
    date = datetime.datetime.fromisoformat(published_at.replace('Z', '+00:00')).date().isoformat()
    checksums = checksums_from(checksum_data)
    assets = {}
    raw_assets = release.get('assets', [])
    if not isinstance(raw_assets, list):
        raise ValueError('Release assets must be an array')
    for asset in raw_assets:
        if not isinstance(asset, dict):
            raise ValueError('Release assets must be objects')
        name = asset.get('name')
        if not isinstance(name, str) or name in assets:
            raise ValueError('Missing or duplicate release asset name')
        assets[name] = asset
    sums_asset = assets.get('SHA256SUMS.txt', {})
    if sums_asset.get('digest') != f'sha256:{sha256(checksum_data)}':
        raise ValueError('SHA256SUMS.txt does not match its GitHub release digest')
    values = {'VERSION': tag[1:], 'TAG': tag, 'RELEASE_DATE': date, 'MACOS_ASSET': macos_asset}
    for prefix, name in {**ASSETS, 'MACOS': macos_asset}.items():
        asset = assets.get(name)
        if asset is None or name not in checksums:
            raise ValueError(f'Missing required asset or checksum: {name}')
        url = f'{REPOSITORY}/releases/download/{tag}/{name}'
        if asset.get('browser_download_url') != url:
            raise ValueError(f'Asset URL must belong to this versioned release: {name}')
        digest = checksums[name]
        if asset.get('digest') != f'sha256:{digest}':
            raise ValueError(f'Checksum and GitHub asset digest disagree: {name}')
        if assets_dir is not None and (assets_dir / name).exists():
            with (assets_dir / name).open('rb') as stream:
                actual = hashlib.file_digest(stream, 'sha256').hexdigest()
            if actual != digest:
                raise ValueError(f'Downloaded asset failed SHA256 verification: {name}')
        values[f'{prefix}_URL'] = url
        values[f'{prefix}_SHA256'] = digest
    return values


def substitute(template, values):
    def replace(match):
        key = match.group(1)
        if key not in values:
            raise ValueError(f'Unknown template variable: {key}')
        return values[key]
    return TOKEN.sub(replace, template)


def rendered_files(values, templates=TEMPLATES):
    files = {}
    for source in sorted(templates.rglob('*')):
        if source.is_file():
            name = substitute(source.relative_to(templates).as_posix(), values)
            files[name] = substitute(source.read_text(), values).encode('utf-8')
    files['flatpak/daccord.png'] = (ROOT / 'dist/icons/icon_256x256.png').read_bytes()
    files['PREPARATION.json'] = (json.dumps({
        'release': values['TAG'],
        'publication_ready': False,
        'macos_asset': values['MACOS_ASSET'],
        'blockers': [
            'Verify platform install, update, uninstall, signatures, and updater opt-out.',
            'Use a release containing package-manager runtime/installer support.',
            'Homebrew requires a signed PACKAGE_MANAGER=true DMG and tap/catalog review.',
            'Flatpak requires runtime/ABI/media/portal checks and native Linux screenshots.',
            'Public catalog submissions, moderation, and publishing credentials are not configured.',
        ],
    }, indent=2) + '\n').encode('utf-8')
    return files


def write_files(files, output, check=False):
    # Rendering/validation completes before any output is touched. Refuse a
    # symlinked output tree so regenerating artifacts cannot follow it elsewhere.
    for relative in files:
        destination = output / relative
        if any(parent.is_symlink() for parent in [destination, *destination.parents]):
            raise ValueError(f'Refusing symlinked output path: {destination}')
    changed = [name for name, contents in files.items()
               if not (output / name).is_file() or (output / name).read_bytes() != contents]
    if check:
        if changed:
            raise ValueError('Generated manifests differ: ' + ', '.join(changed))
        return
    for name in changed:
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + '.tmp')
        if temporary.exists() or temporary.is_symlink():
            raise ValueError(f'Refusing existing temporary file: {temporary}')
        temporary.write_bytes(files[name])
        temporary.replace(destination)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release-json', type=Path, required=True)
    parser.add_argument('--checksums', type=Path, required=True)
    parser.add_argument('--assets-dir', type=Path, help='Also verify downloaded matching assets, when present')
    parser.add_argument('--macos-asset', choices=MACOS_ASSETS, default=MACOS_ASSETS[0])
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/packaging/generated')
    parser.add_argument('--check', action='store_true', help='Compare output without writing')
    args = parser.parse_args(argv)
    try:
        release = json.loads(args.release_json.read_text())
        if not isinstance(release, dict):
            raise ValueError('Release JSON must be an object')
        values = release_values(release, args.checksums.read_bytes(), args.macos_asset, args.assets_dir)
        write_files(rendered_files(values), args.output, args.check)
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f'package manifests: {error}', file=sys.stderr)
        return 1
    print(f'{values["TAG"]}: review-only manifests {"verified" if args.check else "written"} at {args.output}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
