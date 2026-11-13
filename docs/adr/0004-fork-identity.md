# 0004 — RubyFunk application identity

RubyFunk uses `io.github.gunu3371.rubyfunk` across platform package identities, with
`group.io.github.gunu3371.rubyfunk` for Apple shared storage. Executables, modules, services,
configuration paths, environment variables and deep links use the RubyFunk name.

This is a separate install. Apple and Android data stay with their original app identities;
Windows uninstall GUIDs also differ. Pair devices again. Build host, worker, drivers and clients
from the same source revision. Do not replace an upstream library in place: renamed C symbols
and generated enum constants require C ABI 66 and matching headers.

Cryptographic pairing and unlock contexts, ALPN values and wire-version labels retain their
existing definitions. Renaming an application does not redefine a signed message.

Keep original license notices, release history and external project attribution. Vendored code
keeps its identifiers. Update downloads use the fork's repository; signed channel manifests and
platform distribution credentials must be provisioned before publishing releases.
