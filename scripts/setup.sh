#!/usr/bin/env bash
# Install dependencies and run code generation once.
# Run this after cloning or after pulling changes that touch pubspec/codegen.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

log "Checking Linux desktop build dependencies"
install_linux_dev_deps

log "Fetching package dependencies"
$FLUTTER pub get

log "Running code generation (build_runner)"
$DART run build_runner build --delete-conflicting-outputs

log "Setup complete."
