# Identifiers

RubyFunk uses `io.github.gunu3371.rubyfunk`, with lowercase dotted suffixes.
These identifiers belong to the fork. Punktfunk identifiers name separate installs.

| Platform | Identity |
| --- | --- |
| Apple | Bundle `io.github.gunu3371.rubyfunk`, widgets `.widgets`, App Group `group.io.github.gunu3371.rubyfunk` |
| Android | Application id and Kotlin package `io.github.gunu3371.rubyfunk` |
| Linux | Flatpak, GTK, AppStream and icon `io.github.gunu3371.rubyfunk` |
| Windows | MSIX `io.github.gunu3371.rubyfunk`, AUMIDs `.client` and `.tray` |
| GNOME Shell | `rubyfunk-windows@gunu3371.github.io` |

Executables, packages, configuration directories and systemd units use `rubyfunk`.
Windows services and registry product keys use `RubyFunk`, such as `RubyFunkHost`.
The URL scheme is `rubyfunk://`; DNS-SD discovery uses `_rubyfunk._udp`.
C symbols use `rubyfunk_`, Swift modules use `RubyFunk`, and environment variables use `RUBYFUNK_`.

## Install compatibility

The fork has separate Windows uninstall GUIDs. Installing RubyFunk does not upgrade Punktfunk.
Apple keychain groups, App Groups, Android data and host configuration paths also change.
Pair devices again and configure the new install. Keep the old install's data until verified.

Build the host, capture worker, drivers and clients from the same RubyFunk revision.
Punktfunk release artifacts and update feeds are not RubyFunk updates. The fork update feed
points at this repository's release downloads; publishing signed manifests is separate work.
Wire protocol labels `punktfunk/1` and `punktfunk/2`, pairing proofs and unlock signature
contexts retain their existing meanings. Rebuild clients and libraries together for C ABI 66.

## Stable within the fork

Keep bundle IDs, App Groups, Android IDs, Windows uninstall GUIDs and plugin AppContainer
names stable after release. They determine store identity, upgrade matching and access grants.
