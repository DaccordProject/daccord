"""Check the decoded signing profile's Associated Domains authorization."""

import plistlib
import sys


def permits_applinks(profile):
    entitlements = profile.get("Entitlements", {})
    if not isinstance(entitlements, dict):
        return False
    domains = entitlements.get("com.apple.developer.associated-domains", [])
    return isinstance(domains, list) and any(
        domain in ("*", "applinks:www.daccord.gg") for domain in domains
    )


if __name__ == "__main__":
    try:
        allowed = permits_applinks(plistlib.loads(sys.stdin.buffer.read()))
    except (ValueError, TypeError, AttributeError, plistlib.InvalidFileException):
        allowed = False
    sys.exit(0 if allowed else 1)
