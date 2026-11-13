# Boots the NixOS module with the real packages. The host, console and runner units come up from
# the packages' own files plus the module's drop-ins, and the runner keeps the sandbox its shipped
# unit declares. Then the door switches on and off through its helper and polkit rule. It builds
# the host, so only the `ci:nix-rust` lane of nix.yml builds this.
{
  testers,
  module,
}:
testers.runNixOSTest {
  name = "rubyfunk-module";

  nodes.machine = {
    imports = [ module ];
    services.rubyfunk.host = {
      enable = true;
      users = [ "alice" ];
      autoStart = true;
      # A gamescope build of its own, and nothing here needs it.
      gamescopeHdr = false;
    };
    services.rubyfunk.seats.enable = true;
    # Lingering starts alice's manager at boot, as on an appliance. Both may switch the door.
    users.users.alice = {
      isNormalUser = true;
      linger = true;
      extraGroups = [ "rubyfunk-update" ];
    };
    users.users.bob = {
      isNormalUser = true;
      extraGroups = [ "rubyfunk-update" ];
    };
    virtualisation.memorySize = 3072;
  };

  testScript =
    { nodes, ... }:
    ''
    def show(unit, *props):
        args = " ".join(f"-p {p}" for p in props)
        return machine.succeed(f"systemctl --user -M alice@ show {unit} {args}")

    machine.wait_for_unit("multi-user.target")
    for unit in ("rubyfunk-host", "rubyfunk-web", "rubyfunk-scripting"):
        machine.wait_for_unit(f"{unit}.service", "alice")
    # The console serves only once the host has written its token and certificate.
    machine.wait_for_open_port(47990)
    machine.wait_for_open_port(47992)

    # KWin identifies the host by its store path; a wrapper there breaks desktop streaming.
    exec_start = show("rubyfunk-host", "ExecStart")
    assert "-rubyfunk-host-" in exec_start and "/run/wrappers" not in exec_start, exec_start

    sandbox = show(
        "rubyfunk-scripting",
        "NoNewPrivileges",
        "ProtectSystem",
        "ProtectHome",
        "PrivateTmp",
        "ProtectControlGroups",
        "CapabilityBoundingSet",
        "RestartPreventExitStatus",
        "InaccessiblePaths",
    )
    for want in (
        "NoNewPrivileges=yes",
        "ProtectSystem=strict",
        "ProtectHome=tmpfs",
        "PrivateTmp=no",
        "ProtectControlGroups=yes",
        "CapabilityBoundingSet=\n",
        "RestartPreventExitStatus=78",
        "/home/alice/.config/rubyfunk/mgmt-token",
    ):
        assert want in sandbox, f"{want!r} missing from:\n{sandbox}"

    # The door, as a member starts it. No seat starts here: the VM has no GPU.
    seats = "${nodes.machine.services.rubyfunk.seats.package}/libexec/rubyfunk/rubyfunk-seats"
    box = "/var/lib/rubyfunk"
    record = "/var/lib/rubyfunk-seats/owner"

    def switch(user, verb):
        return f"su - {user} -c 'systemctl start rubyfunk-door-{verb}@{user}.service'"

    machine.wait_for_unit("rubyfunk-seats.service")
    machine.succeed(switch("alice", "on"))
    machine.wait_for_unit("rubyfunk-door.service")
    assert machine.succeed(f"cat {record}").strip() == "alice"
    owner = machine.succeed(f"stat -c %U:%G {box}/native-key.pem").strip()
    assert owner == "rubyfunk:rubyfunk-door", owner
    machine.succeed(f"{seats} list | grep -q owner=true")

    # A repeat changes nothing, and another member can't take a door that is on.
    machine.succeed(switch("alice", "on"))
    machine.fail(switch("bob", "on"))
    assert machine.succeed(f"cat {record}").strip() == "alice"

    # What changed on the door goes home with the switch off.
    machine.succeed(f"runuser -u rubyfunk -- sh -c 'echo 7 > {box}/web-session-epoch'")
    machine.succeed(switch("alice", "off"))
    machine.succeed(f"test ! -e {record}")
    machine.fail("systemctl is-active rubyfunk-door.service")
    epoch = machine.succeed("cat /home/alice/.config/rubyfunk/web-session-epoch").strip()
    assert epoch == "7", epoch
  '';
}
