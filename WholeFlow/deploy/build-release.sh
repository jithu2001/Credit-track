#!/usr/bin/env bash
# Builds the WholeFlow release package for client Tally PCs from Linux/macOS:
# the same result as deploy\Build-Release.ps1 on Windows.
#
#   deploy/build-release.sh            # vet + tests, then build and zip
#   deploy/build-release.sh --skip-tests
#
# Releases are unsigned for now (installed by hand on each PC). To sign with
# an Authenticode certificate later (so Windows SmartScreen and antivirus
# trust the exe), osslsigncode uses the certificate as a .pfx file:
#   WF_SIGN_PFX=/path/cert.pfx WF_SIGN_PASS_FILE=/path/pass.txt deploy/build-release.sh
# (WF_SIGN_TIMESTAMP overrides the timestamp server.)
#
# Result (version from internal/syncer/settings.go):
#   dist/WholeFlow-<version>/      wholeflow.exe, Install-WholeFlow.cmd/.ps1,
#                                  README.txt, .env.example
#   dist/WholeFlow-<version>.zip   the same files: copy this to the client PC
set -euo pipefail
cd "$(dirname "$0")/.."                       # the WholeFlow folder

skip_tests=0
for a in "$@"; do
  case $a in
    --skip-tests) skip_tests=1 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done

if [[ $skip_tests = 0 ]]; then
  echo "go vet ./..."; go vet ./...
  echo "go test ./..."; go test ./... >/dev/null || { echo "tests failed; nothing was packaged" >&2; exit 1; }
fi

version=$(sed -n 's/^const Version = "\(.*\)"/\1/p' internal/syncer/settings.go)
[[ -n "$version" ]] || { echo "could not read the version" >&2; exit 1; }
name="WholeFlow-$version"
out="dist/$name"; zip="dist/$name.zip"
rm -rf "$out" "$zip"; mkdir -p "$out"

echo "go build (windows/amd64)"
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -o "$out/wholeflow.exe" ./cmd/server

if [[ -n "${WF_SIGN_PFX:-}" ]]; then
  echo "osslsigncode sign"
  osslsigncode sign -pkcs12 "$WF_SIGN_PFX" -readpass "${WF_SIGN_PASS_FILE:?set WF_SIGN_PASS_FILE}" \
    -h sha256 -n WholeFlow -ts "${WF_SIGN_TIMESTAMP:-http://timestamp.digicert.com}" \
    -in "$out/wholeflow.exe" -out "$out/wholeflow.signed.exe"
  mv "$out/wholeflow.signed.exe" "$out/wholeflow.exe"
  osslsigncode verify -in "$out/wholeflow.exe" >/dev/null || { echo "signature does not verify" >&2; exit 1; }
else
  echo "note: wholeflow.exe is not signed (no WF_SIGN_PFX)" >&2
fi

# Windows text files: CRLF line endings.
crlf() { sed 's/\r$//; s/$/\r/' "$1" > "$2"; }
crlf deploy/Install-WholeFlow.cmd "$out/Install-WholeFlow.cmd"
crlf deploy/Install-WholeFlow.ps1 "$out/Install-WholeFlow.ps1"
crlf deploy/README.md "$out/README.txt"
crlf .env.example "$out/.env.example"

(cd "$out" && zip -qr -X "../$name.zip" .)
hash=$(sha256sum "$out/wholeflow.exe" | cut -d' ' -f1)

echo
echo "Release $version ready:"
echo "  $(pwd)/$zip"
echo "  wholeflow.exe SHA-256 $hash"
echo
echo "On each client PC: extract the zip, double-click Install-WholeFlow.cmd, accept the UAC prompt (see README.txt)."
