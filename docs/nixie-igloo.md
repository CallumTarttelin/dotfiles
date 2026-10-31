# Igloo on nixie

`hosts/default.nix` imports the pinned Igloo runner module for nixie, and
`hosts/nixie/igloo.nix` configures it. It runs as `tarttelin`, listens on
`127.0.0.1:7890`, and schedules at most 8 vCPUs / 16384 MiB (16 GiB) of guest
resources. Private state and the local checkpoint object directory are under
`/var/lib/igloo`.

`services.igloo.memoryMiB` limits the aggregate configured RAM of starting,
running and stopping guests. Requests beyond the available budget queue until
capacity is released; a single request larger than the budget is rejected.
Host and VM-helper memory is additional: this is an admission budget, not a
systemd `MemoryMax` limit on total physical memory consumption.

Likewise, `services.igloo.cpus` is an aggregate vCPU admission budget, not a CPU
quota or affinity mask. It can exceed the host's available CPU threads to allow
CPU overcommit: Linux schedules the VMs' vCPU threads alongside other work.
Idle or bursty guests can share capacity effectively; simultaneous builds
compete for CPU time. Keep the RAM budget conservative unless memory-pressure
monitoring and reclamation are implemented; the runner does not automatically
balloon guests or suspend them under pressure.

The input pins Igloo `971d2a6a3a7d527ff2bff83cffb548c32c87ef81`, including
shared Nix stores, incremental evaluation, live updates, native Wayland desktops,
the optimized minimal initrd with automatic compatibility fallback, project
initialization and automatic local-flake transfer to the remote runner.

The CLI is installed by the shared `igloo-client` module on nixie, nixwork
and nixshark. On nixie it uses the loopback API; on the other hosts it defaults
to `https://igloo.callumtarttelin.com`, served by Caddy using the existing
wildcard certificate. The runner still listens only on loopback and checks its
bearer token on every request. Remote guest SSH, project transfers, forwards and
viewers use `tarttelin@nixie` as their SSH jump host. Nixie enables Tailscale
SSH declaratively; tailnet SSH policy must permit that login.

`secrets/igloo-api.age` contains the existing runner token as an environment
file, encrypted for all configured host and user keys. Agenix decrypts it at
`/run/agenix/igloo-api`, readable only by `tarttelin` and root. The runner loads
that file with `EnvironmentFile`; the client reads it at execution time. No
plaintext credential is included in a Nix derivation or generated Caddy config.
The wrapper respects an explicit `IGLOO_TOKEN`, endpoint or jump-host override,
and only supplies nixie's credential to its configured endpoint.

Activate the configuration on each host to install its CLI and decrypt the
credential. Nixie also needs its Igloo unit and Caddy configuration activated;
the former runtime-only service link was lost on reboot. A full system switch
also changes SSH settings relative to the previously running system; review
those changes before switching, or activate only the relevant units for testing.

From nixwork or nixshark, after activation:

```sh
environment=$(igloo build 'git+https://git.callumtarttelin.com/tarttelin/igloo.git#minimal')
igloo create demo --environment "$environment" --wait
igloo ssh demo
igloo push demo ./my-project
igloo forward demo 8000 --local 8080
igloo rm demo
```

For a new project, `igloo init` creates a missing root `flake.nix` and
`igloo.yml`. If a flake already exists, it leaves every Nix file alone and only
creates a missing YAML file; that YAML expects a `#environment` output or an
explicitly selected alternative. Existing files are never overwritten.

```sh
igloo init
# In a Git project, track the generated files before building:
git add flake.nix igloo.yml
igloo create demo --wait
```

Environment builds run on nixie. Remote clients automatically lock and transfer
local flakes and their input sources through Nix's SSH archive protocol, using
the configured jump host. Nix reuses sources already in nixie's store. Git flake
URLs are fetched on nixie, and `igloo push` copies application files into the
guest workspace. No local source transfer is needed for an already-built
environment hash.

From the project checkout:

```sh
cd ~/Documents/igloo
export IGLOO_STATE_DIR=/var/lib/igloo
nix run . -- create demo --wait
nix run . -- ssh demo
nix run . -- push demo ./my-project
nix run . -- suspend demo --memory --upload
nix run . -- resume demo --wait
nix run . -- rm demo
```

For a desktop:

```sh
environment=$(nix run . -- build .#desktop)
nix run . -- create desktop --environment "$environment" --memory-mib 3072 --wait
nix run . -- view desktop
```

The desktop uses headless Labwc and native Wayland Chromium. Xwayland starts
on demand for legacy applications. Project flakes can select Sway with
`igloo.desktop.compositor = "sway"`. Both support the same controls and viewer.

`view` serves WayVNC through noVNC and an SSH forward to the parent's loopback interface.
The project README covers browser/computer automation and arbitrary webserver
forwards. Inside a guest with a project flake, `igloo update --source
/home/agent/workspace#environment` builds and requests activation; reconnect and
use `igloo update-status` to check the result.

RAM restoration and guest-built updates were tested against an isolated Garage
bucket with fresh credentials. The installed service defaults to its local object
directory. To use Garage persistently, configure a dedicated bucket/key, set
`services.igloo.environmentFile` to a private runtime credentials file, and set
`services.igloo.localObjectDirectory = null`. The required variable names are in
the Igloo README; no existing Garage credentials were copied into this service.

Prepared environment artifacts live in the host Nix store, are pinned by the
runner and shared read-only between boxes with private writable overlays.
`igloo.lib.mkProject` provides opt-in language tools, scripts, environment
variables, processes and cache settings. `nix build .#cache` warms all built-ins;
`minimal`, `desktop` and the example have been built locally. The existing signed
Harmonia cache can serve these ordinary Nix outputs. Detailed timings and the
remaining per-object sharing/GC work are in Igloo's `benchmarks/README.md`.

Client integration was validated on 2026-10-31: all three host configurations
evaluate and their wrappers build with shell checking. Eight routing tests cover
defaults, explicit endpoint/token/jump overrides, argument preservation and
credential isolation. A temporary Caddy route and isolated runner passed HTTPS
authentication, runtime credential loading, VM creation, authenticated guest SSH,
status and teardown checks. The route, VM, runner and temporary plaintext
credential were removed. Cross-host SSH remains to be verified after activation;
nixwork and nixshark were unreachable during this run.

The initializer release additionally passed 20 Rust tests and a real-VM test
using a new Git project: offline initialization, existing-flake preservation,
locking and archiving sources over SSH, creation from the generated profile, a
remote variable edit activated in place with the same guest boot ID, and teardown.

Git fetching is also verified with an empty inherited PATH and fresh HOME. The
packaged runtime supplies Git explicitly; `checks.x86_64-linux.runtime-tools`
checks prerequisite lookup with host tools removed. The exact Git URL used by
the remote smoke test passes through an isolated packaged runner.

Codex skills are managed for the fleet in `home/programs/codex.nix`. Add named
skill directories to its `skills` attribute set; they can come from local
directories or pinned inputs. Igloo's skill uses the same locked input as its CLI. Updating
the lock and rebuilding deploys those skill versions; generation rollback
restores the earlier versions. Home Manager links each declared skill folder
under `~/.codex/skills`, alongside other installed skills. Codex's binary,
`CODEX_HOME`, personal settings and authentication stay under their existing
management. The Codex program module is not enabled just to install skills,
because its XDG behavior would move the configured home directory on these hosts.

On nixie, the original manual skill copy was backed up under
`~/.codex/skill-backups` before activating the managed user generation.
