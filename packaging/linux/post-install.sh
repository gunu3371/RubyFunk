#!/bin/sh
# The host state every rubyfunk-host install shares, run as root once the payload is in place:
# by the deb postinst, pacman's post_install and post_upgrade, rpm's %post and rubyfunk-sysext's
# post_merge. Installed as /usr/libexec/rubyfunk/post-install (/usr/lib/rubyfunk on Arch).
# Capabilities and the first-run hints stay with each format. Every step is best-effort and the
# script exits 0: nothing here may fail an install.

# First: 60-rubyfunk.rules chgrp's the vhci nodes to 'rubyfunk'.
systemd-sysusers rubyfunk.conf >/dev/null 2>&1 || true
# /dev/uinput and /dev/uhid pick up the rule without a reboot (a no-op in a container).
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger --subsystem-match=misc 2>/dev/null || true
# systemd-sysctl applies the UDP buffer sizes at boot; this applies them now.
sysctl -p /usr/lib/sysctl.d/99-rubyfunk-net.conf >/dev/null 2>&1 || true
if [ -f /usr/lib/tmpfiles.d/rubyfunk-seats.conf ]; then
    systemd-tmpfiles --create /usr/lib/tmpfiles.d/rubyfunk-seats.conf >/dev/null 2>&1 || true
fi

# steamos-manager boxes: Valve's ds_inhibit walks /proc on every open of our virtual DualSense's
# hidraw, SELinux denies it at hundreds of AVCs a second and setroubleshootd turns that into a
# box-wide stall. Keyed on the module name, so rename the .cil when its rules change.
CIL=/usr/share/rubyfunk/selinux/rubyfunk-ds-inhibit.cil
if command -v semodule >/dev/null 2>&1 && [ -e /usr/lib/steamos-manager ] && [ -f "$CIL" ] &&
   ! semodule -l 2>/dev/null | grep -qx rubyfunk-ds-inhibit; then
    echo "installing SELinux drop-in 'rubyfunk-ds-inhibit' (silences the steamos-manager ds_inhibit audit flood)…"
    semodule -i "$CIL" ||
        echo "!! semodule -i failed — the ds_inhibit audit flood stays live; see packaging/bazzite/README.md" >&2
fi

# An open firewall keeps the ports a profile had when it was allowed: ufw stores the expanded
# rules, firewalld serves the service it last loaded. Name each profile missing a port this
# package added. `ufw status verbose` prints expanded ports, so it can tell stale from current.
if command -v ufw >/dev/null 2>&1 &&
   ufw status verbose 2>/dev/null | grep -q 'rubyfunk-web' &&
   ! ufw status verbose 2>/dev/null | grep -q '47993'; then
    echo ""
    echo "rubyfunk: your ufw rule for 'rubyfunk-web' predates TCP 47993 (plugin UIs, served"
    echo "  from their own origin). Plugin interfaces will not load in the console until:"
    echo "    sudo ufw app update rubyfunk-web && sudo ufw reload"
fi
if command -v ufw >/dev/null 2>&1 &&
   ufw status verbose 2>/dev/null | grep -q 'rubyfunk-native' &&
   ! ufw status verbose 2>/dev/null | grep -q '9778'; then
    echo ""
    echo "rubyfunk: your ufw rule for 'rubyfunk-native' predates UDP 9778 (browser streaming)."
    echo "  A browser cannot connect to this host until:"
    echo "    sudo ufw app update rubyfunk-native && sudo ufw reload"
fi
# --info-service answers from the definition the daemon loaded, i.e. the stale one.
if command -v firewall-cmd >/dev/null 2>&1 &&
   firewall-cmd --state >/dev/null 2>&1 &&
   firewall-cmd --query-service=rubyfunk-web >/dev/null 2>&1 &&
   ! firewall-cmd --info-service=rubyfunk-web 2>/dev/null | grep -q '47993'; then
    echo ""
    echo "rubyfunk: the rubyfunk-web firewalld service now also covers TCP 47993 (plugin UIs)."
    echo "  Plugin interfaces will not load in the console until:  sudo firewall-cmd --reload"
fi
if command -v firewall-cmd >/dev/null 2>&1 &&
   firewall-cmd --state >/dev/null 2>&1 &&
   firewall-cmd --query-service=rubyfunk-native >/dev/null 2>&1 &&
   ! firewall-cmd --info-service=rubyfunk-native 2>/dev/null | grep -q '9778'; then
    echo ""
    echo "rubyfunk: the rubyfunk-native firewalld service now also covers UDP 9778 (browser"
    echo "  streaming). A browser cannot connect to this host until:  sudo firewall-cmd --reload"
fi

# A Bazzite sysext pins the Fedora major, so a rebase refuses it, /usr/bin/rubyfunk-sysext
# included. Keep that script in /etc with a unit that fetches the new base's image at boot.
MARKER=/usr/lib/extension-release.d/extension-release.rubyfunk
if [ -x /usr/bin/rubyfunk-sysext ] && grep -qs '^VERSION_ID=' "$MARKER"; then
    install -Dm0755 /usr/bin/rubyfunk-sysext /etc/rubyfunk/rubyfunk-sysext || true
    cat > /etc/systemd/system/rubyfunk-sysext-rebase.service <<'EOF'
[Unit]
Description=RubyFunk host: fetch the sysext for a rebased OS
ConditionPathExists=/var/lib/extensions/rubyfunk.raw
ConditionPathExists=!/usr/lib/extension-release.d/extension-release.rubyfunk
Wants=network-online.target
After=network-online.target systemd-sysext.service firewalld.service

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/rubyfunk/rubyfunk-sysext update
TimeoutStartSec=20min
Restart=on-failure
RestartSec=2min

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable rubyfunk-sysext-rebase.service >/dev/null 2>&1 ||
        echo "!! rubyfunk-sysext-rebase.service not enabled: after a Bazzite major rebase, run rubyfunk-sysext update by hand" >&2
fi

# A Moonlight-compatible host (Sunshine, Apollo, …) next to this one: the host's own detector
# prints the warning and exits 1.
if command -v rubyfunk-host >/dev/null 2>&1 &&
   ! conflict="$(rubyfunk-host detect-conflicts 2>/dev/null)"; then
    echo ""
    echo "$conflict"
fi
exit 0
