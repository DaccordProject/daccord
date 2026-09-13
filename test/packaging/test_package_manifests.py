"""Offline generator tests; run with Python 3.11 or later."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('package_manifests', ROOT / 'scripts/package_manifests.py')
PACKAGING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGING)


def fixture():
    names = [*PACKAGING.ASSETS.values(), PACKAGING.MACOS_ASSETS[0]]
    sums = ''.join(f'{PACKAGING.sha256(name.encode())}  {name}\n' for name in names).encode()
    assets = [{
        'name': name,
        'digest': 'sha256:' + PACKAGING.sha256(name.encode()),
        'browser_download_url': f'{PACKAGING.REPOSITORY}/releases/download/v1.2.3/{name}',
    } for name in names]
    assets.append({'name': 'SHA256SUMS.txt', 'digest': 'sha256:' + PACKAGING.sha256(sums)})
    return {'tag_name': 'v1.2.3', 'published_at': '2026-09-12T17:22:04Z', 'assets': assets}, sums


class PackageManifestsTest(unittest.TestCase):
    def setUp(self):
        self.release, self.sums = fixture()

    def test_generates_all_managers_with_matching_version_and_no_placeholders(self):
        files = PACKAGING.rendered_files(PACKAGING.release_values(self.release, self.sums))
        for name, content in files.items():
            self.assertNotIn('@@', name)
            if name.endswith('.png'):
                continue
            self.assertNotIn(b'@@', content, name)
            if name.endswith('.json'):
                json.loads(content)
            if name.endswith(('.xml', '.nuspec')):
                ET.fromstring(content)
        self.assertIn('winget/manifests/d/DaccordProject/Daccord/1.2.3/DaccordProject.Daccord.installer.yaml', files)
        self.assertIn('scoop/daccord.json', files)
        self.assertIn('chocolatey/tools/chocolateyInstall.ps1', files)
        self.assertIn('homebrew/Casks/daccord.rb', files)
        self.assertIn('flatpak/io.github.DaccordProject.daccord.json', files)
        self.assertFalse(json.loads(files['PREPARATION.json'])['publication_ready'])

    def test_installer_hashes_are_bound_to_release_urls(self):
        values = PACKAGING.release_values(self.release, self.sums)
        for prefix, name in PACKAGING.ASSETS.items():
            self.assertEqual(values[prefix + '_SHA256'], PACKAGING.sha256(name.encode()))
            self.assertEqual(values[prefix + '_URL'], f'{PACKAGING.REPOSITORY}/releases/download/v1.2.3/{name}')

    def test_rejects_checksum_file_tampering(self):
        with self.assertRaisesRegex(ValueError, 'SHA256SUMS'):
            PACKAGING.release_values(self.release, self.sums + b'\n')

    def test_rejects_asset_digest_mismatch(self):
        self.release['assets'][0]['digest'] = 'sha256:' + '0' * 64
        with self.assertRaisesRegex(ValueError, 'disagree'):
            PACKAGING.release_values(self.release, self.sums)

    def test_rejects_malformed_duplicate_and_path_checksums(self):
        for sums in [b'invalid', self.sums + self.sums, ('a' * 64 + '  ../file.exe\n').encode()]:
            with self.assertRaises(ValueError):
                PACKAGING.checksums_from(sums)

    def test_rejects_tag_injection_and_unstable_releases(self):
        for tag in ['v1.2.3;evil', '../1.2.3', 'v1.2.3-beta', 'v01.2.3', 'latest']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release = {**self.release, 'tag_name': tag}
                PACKAGING.release_values(release, self.sums)
        for field in ['draft', 'prerelease']:
            with self.assertRaises(ValueError):
                PACKAGING.release_values({**self.release, field: True}, self.sums)

    def test_rejects_wrong_release_or_external_asset_urls(self):
        for url in ['https://evil.test/installer.exe', f'{PACKAGING.REPOSITORY}/releases/download/v9.9.9/daccord-windows-x86_64-setup.exe']:
            release = copy.deepcopy(self.release)
            release['assets'][0]['browser_download_url'] = url
            with self.assertRaisesRegex(ValueError, 'versioned release'):
                PACKAGING.release_values(release, self.sums)

    def test_rejects_missing_duplicate_or_malformed_assets(self):
        for assets in [self.release['assets'][1:], self.release['assets'] * 2, ['bad'], {}]:
            with self.assertRaises(ValueError):
                PACKAGING.release_values({**self.release, 'assets': assets}, self.sums)

    def test_downloaded_assets_are_verified_when_supplied(self):
        name = PACKAGING.ASSETS['WINDOWS_PORTABLE']
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / name).write_bytes(name.encode())
            PACKAGING.release_values(self.release, self.sums, assets_dir=directory)
            (directory / name).write_bytes(b'corrupt')
            with self.assertRaisesRegex(ValueError, 'Downloaded asset'):
                PACKAGING.release_values(self.release, self.sums, assets_dir=directory)

    def test_rendering_is_repeatable_and_check_never_mutates(self):
        values = PACKAGING.release_values(self.release, self.sums)
        files = PACKAGING.rendered_files(values)
        self.assertEqual(files, PACKAGING.rendered_files(values))
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            PACKAGING.write_files(files, output)
            PACKAGING.write_files(files, output, check=True)
            target = output / 'scoop/daccord.json'
            target.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'differ'):
                PACKAGING.write_files(files, output, check=True)
            self.assertEqual(target.read_bytes(), b'changed')

    def test_updater_hooks_do_not_relocate_or_delete_personal_data(self):
        files = PACKAGING.rendered_files(PACKAGING.release_values(self.release, self.sums))
        scoop = json.loads(files['scoop/daccord.json'])
        self.assertNotIn('persist', scoop)
        self.assertEqual(scoop['bin'], 'daccord.exe')
        self.assertIn('daccord.package-manager', scoop['post_install'])
        self.assertIn(b'/PACKAGE_MANAGER=chocolatey', files['chocolatey/tools/chocolateyInstall.ps1'])
        cask = files['homebrew/Casks/daccord.rb'].decode()
        self.assertNotIn('postflight', cask)
        self.assertIn('zap trash: "~/Library/Caches/com.cattrall.daccord"', cask)
        self.assertIn(b'export DACCORD_PACKAGE_MANAGER=flatpak', files['flatpak/daccord'])

    def test_flatpak_ids_dependencies_and_sandbox_are_consistent(self):
        files = PACKAGING.rendered_files(PACKAGING.release_values(self.release, self.sums))
        manifest = json.loads(files['flatpak/io.github.DaccordProject.daccord.json'])
        self.assertEqual(manifest['app-id'], 'io.github.DaccordProject.daccord')
        self.assertNotIn('--filesystem=home', manifest['finish-args'])
        self.assertIn('--talk-name=org.freedesktop.secrets', manifest['finish-args'])
        self.assertIn('--socket=pulseaudio', manifest['finish-args'])
        self.assertIn('--filesystem=xdg-run/pipewire-0:ro', manifest['finish-args'])
        for module in manifest['modules'][:-1]:
            self.assertRegex(module['sources'][0]['commit'], r'^[0-9a-f]{40}$')
        self.assertEqual(manifest['modules'][-1]['sources'][0]['strip-components'], 0)
        metadata = ET.fromstring(files['flatpak/io.github.DaccordProject.daccord.metainfo.xml'])
        self.assertEqual(metadata.findtext('id'), manifest['app-id'])
        self.assertEqual(metadata.find('releases/release').attrib['version'], '1.2.3')

    def test_unknown_template_tokens_fail_instead_of_leaving_invalid_manifests(self):
        with self.assertRaisesRegex(ValueError, 'Unknown template'):
            PACKAGING.substitute('@@UNKNOWN_SHA256@@', {})


if __name__ == '__main__':
    unittest.main()
