#!/usr/bin/env bash
# Builds a release of both apps (WholeFlow Owner and Staff): the Play Store
# bundles (.aab) and installable APKs, signed with the upload key from
# android/key.properties, shrunk with R8 and with obfuscated Dart code.
#
#   tool/build_release.sh             # next version (1.0.5 -> 1.0.6, build +1), asks first
#   tool/build_release.sh --yes       # no question (CI)
#   tool/build_release.sh --no-bump   # rebuild the version in pubspec.yaml as it is
#
# Each run raises the last number of the version name and the build number
# (the Android versionCode, which Google Play needs higher on every upload)
# in pubspec.yaml. The build number goes above every one used before: the
# current one, the app-* tags and earlier versions of pubspec.yaml. If the
# build fails, pubspec.yaml is put back.
#
# Result in build/release/<version>/:
#   WholeFlow-Owner-<version>.aab, WholeFlow-Staff-<version>.aab   upload to Play Console
#   WholeFlow-Owner-<version>.apk, WholeFlow-Staff-<version>.apk   install directly (adb install / share)
# Symbols for reading crash stacks: build/symbols/<flavor>/ (bundles) and
# build/symbols/<flavor>-apk/ (APKs); keep them with the release.
# Afterwards: commit pubspec.yaml and tag the release (git tag app-<version>).
set -euo pipefail

cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }

yes=0 bump=1
for a in "$@"; do
  case $a in
    --yes) yes=1 ;;
    --no-bump) bump=0 ;;
    *) die "unknown option $a" ;;
  esac
done

[[ -f android/key.properties ]] || die "android/key.properties is missing (copy android/key.properties.example; README \"Release builds\")."
store=$(sed -n 's/^storeFile=//p' android/key.properties)
[[ -n "$store" ]] || die "android/key.properties has no storeFile."
if [[ "$store" = /* ]]; then path="$store"; else path="android/app/$store"; fi
[[ -f "$path" ]] || die "the keystore in key.properties ($store) does not exist."
[[ -f env/hosted.json ]] || die "env/hosted.json is missing."

current=$(sed -n 's/^version: *//p' pubspec.yaml)
[[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(\+([0-9]+))?$ ]] || die "pubspec.yaml version '$current' is not x.y.z or x.y.z+build."
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]} cur_build=${BASH_REMATCH[5]:-0}

# Highest build number used so far: released tags and every version pubspec.yaml has had.
last_tag=$(git tag --list 'app-*' | sed -n 's/^app-.*+\([0-9]*\)$/\1/p' | sort -n | tail -1)
last_hist=$(git log -p --format= -- pubspec.yaml 2>/dev/null | sed -n 's/^[-+]version: *[0-9.]*+\([0-9]*\) *$/\1/p' | sort -n | tail -1)
last=$(printf '%s\n' "${last_tag:-0}" "${last_hist:-0}" | sort -n | tail -1)

if [[ $bump = 1 ]]; then
  build=$(( (cur_build > last ? cur_build : last) + 1 ))
  version="$major.$minor.$((patch + 1))+$build"
else
  [[ $cur_build -gt 0 ]] || die "pubspec.yaml version '$current' has no build number (+N); run without --no-bump."
  version=$current build=$cur_build
  if [[ -n "$last_tag" && "$build" -le "$last_tag" ]]; then
    die "build number $build is not above the last released one ($last_tag, tag app-*). Run without --no-bump."
  fi
fi
if git rev-parse -q --verify "refs/tags/app-$version" >/dev/null; then
  die "app-$version is already tagged as released."
fi
[[ -z "$(git status --porcelain -- . 2>/dev/null)" ]] || echo "warning: wholeflow_app has uncommitted changes."

echo "WholeFlow Owner and Staff: $current -> $version (versionCode $build; highest used so far ${last})."
if [[ $yes = 0 ]]; then
  read -r -p "Build? [y/N] " ok
  [[ "$ok" == [yY]* ]] || exit 1
fi

if [[ $bump = 1 ]]; then
  cp pubspec.yaml pubspec.yaml.bak
  # A failed build must not use up the number: put the old version back.
  trap '[[ -f pubspec.yaml.bak ]] && mv pubspec.yaml.bak pubspec.yaml && echo "build failed: pubspec.yaml left at $current" >&2' EXIT
  sed -i "s/^version: *.*/version: $version/" pubspec.yaml
fi

flutter pub get
for flavor in owner staff; do
  common=(--release --flavor "$flavor" -t "lib/main_$flavor.dart" --obfuscate --dart-define-from-file=env/hosted.json)
  flutter build appbundle "${common[@]}" --split-debug-info="build/symbols/$flavor"
  flutter build apk "${common[@]}" --split-debug-info="build/symbols/$flavor-apk"
done

out="build/release/$version"
rm -rf "$out"; mkdir -p "$out"
for flavor in owner staff; do
  Name=$(tr '[:lower:]' '[:upper:]' <<< "${flavor:0:1}")${flavor:1}
  cp "build/app/outputs/bundle/${flavor}Release/app-$flavor-release.aab" "$out/WholeFlow-$Name-$version.aab"
  cp "build/app/outputs/flutter-apk/app-$flavor-release.apk" "$out/WholeFlow-$Name-$version.apk"
done

if [[ $bump = 1 ]]; then rm -f pubspec.yaml.bak; trap - EXIT; fi

echo
echo "Release $version:"
ls -1 "$out"
echo
echo "Play Console: upload the .aab files. Direct install: adb install -r $out/WholeFlow-Owner-$version.apk"
echo "(An APK signed with the upload key can't update an app installed from Play; uninstall that first.)"
echo "Symbols (keep for this version): build/symbols/owner, staff, owner-apk, staff-apk"
echo "Then: git commit -m 'Apps $version' pubspec.yaml && git tag app-$version"
