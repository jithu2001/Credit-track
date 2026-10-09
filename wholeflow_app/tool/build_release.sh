#!/usr/bin/env bash
# Builds the Play Store bundles of both apps (WholeFlow Owner and Staff):
# signed with the upload key from android/key.properties, shrunk with R8 and
# with obfuscated Dart code. The symbols for reading crash stacks are kept in
# build/symbols/<flavor>/ — keep them with the release (one folder per version).
#
#   tool/build_release.sh          # asks before building
#   tool/build_release.sh --yes    # no question (CI)
#
# Afterwards: upload build/app/outputs/bundle/<flavor>Release/app-<flavor>-release.aab
# to each app in Play Console, then tag the release: git tag app-<version>.
set -euo pipefail

cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }

[[ -f android/key.properties ]] || die "android/key.properties is missing (copy android/key.properties.example; README \"Release builds\")."
store=$(sed -n 's/^storeFile=//p' android/key.properties)
[[ -n "$store" ]] || die "android/key.properties has no storeFile."
if [[ "$store" = /* ]]; then path="$store"; else path="android/app/$store"; fi
[[ -f "$path" ]] || die "the keystore in key.properties ($store) does not exist."
[[ -f env/hosted.json ]] || die "env/hosted.json is missing."

version=$(sed -n 's/^version: *//p' pubspec.yaml)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || die "pubspec.yaml version '$version' is not <name>+<build>."
build=${version#*+}

# Google Play refuses a versionCode it has seen before: each upload needs a
# higher build number (the part after +) in pubspec.yaml.
last=$(git tag --list 'app-*' | sed -n 's/^app-.*+\([0-9]*\)$/\1/p' | sort -n | tail -1)
if [[ -n "$last" && "$build" -le "$last" ]]; then
  die "build number $build is not above the last released one ($last, tag app-*). Bump 'version:' in pubspec.yaml."
fi
if git rev-parse -q --verify "refs/tags/app-$version" >/dev/null; then
  die "app-$version is already tagged as released. Bump 'version:' in pubspec.yaml."
fi
[[ -z "$(git status --porcelain -- . 2>/dev/null)" ]] || echo "warning: wholeflow_app has uncommitted changes."

echo "Building WholeFlow Owner and Staff $version (versionCode $build${last:+, last released $last})."
if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Continue? [y/N] " ok
  [[ "$ok" == [yY]* ]] || exit 1
fi

flutter pub get
for flavor in owner staff; do
  flutter build appbundle --release --flavor "$flavor" -t "lib/main_$flavor.dart" \
    --obfuscate --split-debug-info="build/symbols/$flavor" \
    --dart-define-from-file=env/hosted.json
done

echo
echo "Bundles:"
ls -1 build/app/outputs/bundle/*Release/*.aab
echo "Symbols (keep for this version): build/symbols/owner, build/symbols/staff"
echo "After uploading: git tag app-$version"
