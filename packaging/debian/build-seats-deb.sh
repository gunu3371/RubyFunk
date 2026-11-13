#!/usr/bin/env bash
# Build the rubyfunk-seats .deb: the root supervisor that runs a user, a logind session and a
# host per profile seat, and the door's units and root helper (reachable without logging in).
# The host .deb depends on it. Installed, never enabled: the console turns seats and the door on.
#
# The binary is built beside the host in the same cargo pass (deb.yml), on the Ubuntu 24.04 image,
# so one package serves 24.04 through 26.04. Without a prebuilt binary the script builds it.
#
# Usage: VERSION=0.0.1~ci42.gdeadbee [ARCH=amd64] bash packaging/debian/build-seats-deb.sh
# Output: dist/rubyfunk-seats_<version>_<arch>.deb
set -euo pipefail

VERSION="${VERSION:?set VERSION (e.g. 0.0.1 or 0.0.1~ci42.gdeadbee)}"
ARCH="${ARCH:-amd64}"
PKG="rubyfunk-seats"
ROOTDIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOTDIR"

BIN="target/release/$PKG"
if [ ! -x "$BIN" ]; then
  echo "==> building $PKG (release)"
  cargo build --release --locked -p rubyfunk-seats
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
DOCDIR="$STAGE/usr/share/doc/$PKG"

# --- file layout (matches the RPM %install) ----------------------------------
LIBEXEC="$STAGE/usr/libexec/rubyfunk"
install -Dm0755 "$BIN" "$LIBEXEC/$PKG"
for f in seat-session seat-reap; do
  install -Dm0755 "packaging/linux/$f" "$LIBEXEC/$f"
done
for f in rubyfunk-seats.service rubyfunk-seat@.service; do
  install -Dm0644 "packaging/linux/$f" "$STAGE/usr/lib/systemd/system/$f"
done
install -Dm0644 packaging/linux/rubyfunk-seats-user.conf "$STAGE/usr/lib/systemd/system/user@.service.d/50-rubyfunk-seats.conf"
install -Dm0644 packaging/linux/rubyfunk-seat.pam "$STAGE/usr/lib/pam.d/rubyfunk-seat"
install -Dm0644 packaging/linux/rubyfunk-seats.tmpfiles "$STAGE/usr/lib/tmpfiles.d/rubyfunk-seats.conf"
install -Dm0644 packaging/linux/65-rubyfunk-seats.rules "$STAGE/usr/lib/udev/rules.d/65-rubyfunk-seats.rules"
install -Dm0755 packaging/linux/door-helper "$LIBEXEC/door-helper"
for f in rubyfunk-door.service rubyfunk-web-door.service rubyfunk-door-on@.service rubyfunk-door-off@.service; do
  install -Dm0644 "packaging/linux/$f" "$STAGE/usr/lib/systemd/system/$f"
done
install -Dm0644 packaging/linux/49-rubyfunk-door.rules "$STAGE/usr/share/polkit-1/rules.d/49-rubyfunk-door.rules"
install -Dm0644 LICENSE-MIT    "$DOCDIR/LICENSE-MIT"
install -Dm0644 LICENSE-APACHE "$DOCDIR/LICENSE-APACHE"

cat > "$DOCDIR/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: rubyfunk
Source: https://github.com/gunu3371/RubyFunk

Files: *
Copyright: unom and the rubyfunk contributors
License: MIT or Apache-2.0
 Dual-licensed. Full texts in /usr/share/doc/$PKG/LICENSE-MIT and
 /usr/share/doc/$PKG/LICENSE-APACHE.
EOF
printf '%s (%s) stable; urgency=medium\n\n  * Automated build %s.\n\n -- unom <packages@unom.io>  %s\n' \
  "$PKG" "$VERSION" "$VERSION" "$(date -uR 2>/dev/null || echo 'Thu, 01 Jan 1970 00:00:00 +0000')" \
  | gzip -9n > "$DOCDIR/changelog.Debian.gz"

# --- dependencies ------------------------------------------------------------
SHLIB_TMP="$(mktemp -d)"
mkdir -p "$SHLIB_TMP/debian"
cat > "$SHLIB_TMP/debian/control" <<EOF
Source: $PKG

Package: $PKG
Architecture: any
Depends: \${shlibs:Depends}
EOF
SHDEPS="$(cd "$SHLIB_TMP" && dpkg-shlibdeps -O --ignore-missing-info "$ROOTDIR/$BIN" 2>/dev/null \
          | sed -n 's/^shlibs:Depends=//p')"
rm -rf "$SHLIB_TMP"
[ -n "$SHDEPS" ] || { echo "dpkg-shlibdeps produced no deps — is dpkg-dev installed?" >&2; exit 1; }

# What the supervisor and the door helper run: useradd/groupadd/usermod, runuser and setpriv,
# setfacl, loginctl/systemctl, pkill. The host depends on this package at its own version, so the
# two move together without a loop back.
DEPENDS="$SHDEPS, passwd, util-linux, acl, systemd, procps"

INSTALLED_KB="$(du -k -s "$STAGE" | cut -f1)"

install -d "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: $ARCH
Maintainer: unom <packages@unom.io>
Installed-Size: $INSTALLED_KB
Section: net
Priority: optional
Homepage: https://github.com/gunu3371/RubyFunk
Depends: $DEPENDS
Description: rubyfunk seat supervisor (a user, a session and a host per profile)
 The root daemon behind profile seats. Each seat is a system user with its own logind
 session, a headless desktop and a stock rubyfunk host. The package also carries the
 door units, which keep the box reachable with nobody logged in.
 .
 Installed but not enabled: the console turns seats and the door on. Stopping or
 restarting the daemon leaves running seats up.
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
# The host's postinst, configured after this package, makes the directories and restarts the
# daemon and the door.
if [ "$1" = "configure" ] && [ -d /run/systemd/system ]; then
    systemctl daemon-reload || true
fi
exit 0
EOF
cat > "$STAGE/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] && [ -d /run/systemd/system ]; then
    # door-helper enables the door's units, so removal disables them.
    systemctl disable --now rubyfunk-web-door.service rubyfunk-door.service rubyfunk-seats.service || true
fi
exit 0
EOF
cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
case "$1" in remove|purge)
    if [ -d /run/systemd/system ]; then systemctl daemon-reload || true; fi ;;
esac
exit 0
EOF
chmod 0755 "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm" "$STAGE/DEBIAN/postrm"

mkdir -p dist
OUT="dist/${PKG}_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT" >/dev/null
echo "built $OUT"
echo "  Depends: $DEPENDS"
dpkg-deb -I "$OUT" | sed -n 's/^/  /p' | grep -E 'Version|Installed-Size' || true
