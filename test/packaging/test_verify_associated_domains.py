"""Tests for scripts/verify-associated-domains.py."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/verify-associated-domains.py'
SPEC = importlib.util.spec_from_file_location('verify_associated_domains', SCRIPT)
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)

KEY = 'com.apple.developer.associated-domains'


def profile(domains=None):
    entitlements = {'application-identifier': 'TEAM.gg.daccord.app'}
    if domains is not None:
        entitlements[KEY] = domains
    return {'Name': 'Daccord iOS App Store', 'Entitlements': entitlements}


def run_script(data):
    return subprocess.run([sys.executable, str(SCRIPT)], input=data, capture_output=True).returncode


class PermitsApplinksTest(unittest.TestCase):
    def test_wildcard_string(self):
        self.assertTrue(VERIFY.permits_applinks(profile('*')))

    def test_wildcard_in_list(self):
        self.assertTrue(VERIFY.permits_applinks(profile(['*'])))

    def test_explicit_matching_domain(self):
        self.assertTrue(VERIFY.permits_applinks(profile(['applinks:other.example', 'applinks:www.daccord.gg'])))

    def test_explicit_matching_domain_string(self):
        self.assertTrue(VERIFY.permits_applinks(profile('applinks:www.daccord.gg')))

    def test_missing_entitlement(self):
        self.assertFalse(VERIFY.permits_applinks(profile()))

    def test_non_matching_domain(self):
        self.assertFalse(VERIFY.permits_applinks(profile(['applinks:daccord.gg', 'webcredentials:www.daccord.gg'])))

    def test_non_matching_domain_string(self):
        self.assertFalse(VERIFY.permits_applinks(profile('applinks:example.com')))

    def test_empty_list(self):
        self.assertFalse(VERIFY.permits_applinks(profile([])))

    def test_malformed_entitlements(self):
        self.assertFalse(VERIFY.permits_applinks({'Entitlements': ['*']}))
        self.assertFalse(VERIFY.permits_applinks(profile({'*': True})))


class ScriptExitCodeTest(unittest.TestCase):
    def test_wildcard_string_profile_passes(self):
        self.assertEqual(run_script(plistlib.dumps(profile('*'))), 0)

    def test_non_matching_profile_fails(self):
        self.assertEqual(run_script(plistlib.dumps(profile(['applinks:example.com']))), 1)

    def test_garbage_input_fails(self):
        self.assertEqual(run_script(b'not a plist'), 1)


if __name__ == '__main__':
    unittest.main()
