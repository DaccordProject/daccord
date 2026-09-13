# Package-manager preparation

These are review templates, not published catalog entries. Generate concrete
manifests using `scripts/package_manifests.py`; see
[packaging instructions](../../docs/packaging.md) for inputs, local validation,
updater requirements, and publication blockers.

`reference/` records the published v0.2.20 asset metadata and checksum list.
That release predates package-manager updater support and must not be submitted
using these templates. `templates/` is the maintained source; generated output
is a disposable review artifact.

No package-manager credentials are needed to regenerate or inspect manifests.
