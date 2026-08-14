#!/bin/sh
# Installs pano from a GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/KovskySpring/pano/main/scripts/install.sh | sh
#
# Overridable: PANO_VERSION (default: latest), PANO_BIN_DIR (default:
# ~/.local/bin).
#
# pano is an escript - a single platform-independent file - so there is one
# artifact for every OS and architecture. What it needs is a compatible
# runtime, which is what this script checks for.
set -eu

REPO=KovskySpring/pano
VERSION=${PANO_VERSION:-latest}
BIN_DIR=${PANO_BIN_DIR:-$HOME/.local/bin}

die() {
  echo "install.sh: $1" >&2
  exit 1
}

command -v erl >/dev/null 2>&1 || die "Erlang/OTP 27+ is required but 'erl' is not on PATH"
otp=$(erl -noshell -eval 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().')
if [ "$otp" -lt 27 ] 2>/dev/null; then
  die "Erlang/OTP 27 or newer is required, found OTP $otp"
fi

# libvips does the re-encoding and a JVM runs libGDX TexturePacker. Neither is
# bundled; warn rather than fail, since `pano` checks both again at run time -
# vips only if the config declares a `[compression]` table anywhere, java
# unconditionally since every pack job needs the JVM.
command -v vips >/dev/null 2>&1 \
  || echo "install.sh: warning: no 'vips' on PATH; install libvips 8.15+ ('brew install vips', 'apt install libvips-tools')" >&2
command -v java >/dev/null 2>&1 \
  || echo "install.sh: warning: no 'java' on PATH; pano needs a JVM (Java 8+) to run libGDX TexturePacker" >&2

if [ "$VERSION" = latest ]; then
  url=https://github.com/$REPO/releases/latest/download/pano
else
  url=https://github.com/$REPO/releases/download/$VERSION/pano
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "install.sh: downloading pano ($VERSION)"
curl -fsSL "$url" -o "$tmp/pano" || die "could not download $url"
chmod +x "$tmp/pano"
"$tmp/pano" --help >/dev/null 2>&1 || die "downloaded escript did not run"

mkdir -p "$BIN_DIR"
mv "$tmp/pano" "$BIN_DIR/pano"

echo "install.sh: installed $BIN_DIR/pano"
case :$PATH: in
  *:$BIN_DIR:*) ;;
  *) echo "install.sh: add $BIN_DIR to your PATH to use 'pano'" >&2 ;;
esac
