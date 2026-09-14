# Security policy

## Reporting a vulnerability

**Please do not open a public issue for anything exploitable.**

Report it privately through GitHub's security advisories:

**https://github.com/daMustermann/rocm-wsl-ai/security/advisories/new**

(Security tab → *Report a vulnerability*.) This project has no dedicated security
email address, and public issues are the wrong channel for anything that could be
used against another user before a fix exists.

A useful report contains:

- What an attacker gains, and what they need in order to gain it (a file they must
  be able to write, a repository you must register, a config value you must paste in).
- A minimal reproduction: the config line, the command, or the repository that
  triggers it — plus the affected file, ideally at a commit hash.
- Your toolkit version (`cat VERSION`, and/or `git rev-parse --short HEAD`), your
  Ubuntu version, and whether you are on WSL2.
- Whether the issue is reachable from a *default* installation, or only after the
  user pastes in configuration from somewhere else. That distinction changes the
  severity a lot here.

What to expect: this is a small, volunteer-run project. There is no bug bounty, no
24-hour SLA, and no full-time security team. Reports are read and triaged on a
best-effort basis; a clear reproduction is what makes that fast. Credit in the fix's
`CHANGELOG.md` entry is offered unless you prefer otherwise, and coordinated
disclosure is appreciated — please give a reasonable window before publishing.

---

## What this project is, in security terms

It is **bash and Python 3 scripts that you run inside WSL2 as your own Linux user**.
There is no daemon, no service account, no compiled binary from this repository, and
no server of its own. The one native component it builds is AMD's `ROCm/librocdxg`,
cloned from AMD's repository at install time.

That shape determines the whole threat model:

- The scripts run **with your privileges**, so they can read and write everything you
  can, including the Windows filesystem exposed under `/mnt/c`.
- The installer uses **`sudo`** for the parts that need it: `apt` package
  installation, adding the Charm (gum) apt repository, installing AMD's
  `amdgpu-install` package (which registers `repo.radeon.com` as an apt source),
  `apt install rocm`, and building and installing `librocdxg`. Those steps change
  the distribution, and they are the moments where a malicious or tampered script
  would have the most to gain.
- The toolkit **does not handle secrets**. It never asks for an API token, password,
  SSH key or cloud credential, and it has no telemetry. `perf_engine.py` imports only
  the standard library and makes no network requests at all. Network access happens
  where you would expect it: `git clone`, `apt`, and `pip` installing PyTorch wheels
  from AMD's index.
- **Integrity is whatever the transport provides.** ROCm and `gum` come from apt
  repositories and are GPG-verified by apt, and everything is fetched over HTTPS —
  but the toolkit itself checks no checksums or signatures, and it clones third-party
  repositories at whatever commit the remote serves at that moment.
- **You** are the trust anchor. Almost everything below is about configuration that
  the toolkit *executes* by design, which is exactly why it should only ever come
  from you.

---

## The real risks

These are the parts of the design worth being suspicious about. They are listed as
risks, not as bugs: most of them are deliberate and documented in the code.

### 1. Configuration files are executed, not parsed

`~/.config/rocm-wsl-ai/user.env`, `gpu.env` and `perf.env` are loaded with
`set -a` + `.` (source) by `ai_load_env` in `lib/launch.sh` and by `load_user_env` in
`lib/common.sh`. Sourcing a shell file runs it.

The consequence: **anything in those files executes as you, on every launch**, and
the same is true for anything you paste into them. A "handy `user.env` snippet" from
a forum post, an issue comment, a gist or a model card is equivalent to a script from
that author, even if it looks like a list of `export`s. A history expansion, a
backtick, or a `$(...)` inside a value is code.

This is the toolkit's primary injection surface, and it is a *user-supplied config*
surface rather than a remote one. If you believe a value that arrives from somewhere
other than the user can reach one of these files, that is a genuine vulnerability —
please report it.

Note also that environment variables set this way are inherited by every launched
tool, so a token you export in `user.env` (for example a Hugging Face token, which
`kohya_ss` and some ComfyUI nodes will happily pick up) is visible to all of them,
and may end up in a log or a process listing.

### 2. `tools.local` is a list of shell commands

The generic third-party registry exists so a user can install any Git repository.
Its format is inherited from the built-in registry and its fields are *not* inert
data:

- The `install-dir` field is expanded with `eval` in `rocm_ai_registry_field()`
  (`lib/tools.sh`), because entries are allowed to contain `$HOME`.
- The command field of a locally registered tool is executed through
  `bash -c "cd <dir> && exec <command>"` in `ai_launch()` (`lib/launch.sh`).
- `ROCM_AI_COMFYUI_ARGS` from `perf.env` is word-split straight into that command
  line.

So treat `~/.config/rocm-wsl-ai/tools.local` as a shell script that runs whenever you
launch the tool it describes. Registering a repository that someone else chose, or
copying a `tools.local` line out of an issue, is the same class of decision as
running their script.

### 3. Third-party repositories are trusted, not sandboxed

Registering a repository (built-in or your own) means the toolkit will:

- `git clone --depth=1 --recurse-submodules` it from any host you name. Submodules
  can point at other hosts; nothing validates them.
- `pip install -r requirements.txt` from that checkout. Pip executes the project's
  build backend (`setup.py` / PEP 517 hooks) as you — that is arbitrary code
  execution by design, before the tool has ever started.
- Run whatever start command is configured, in a shell.

There is no signature verification, no pinned commit, no allow-list and no sandbox.
The pull request you reviewed is not necessarily the commit that gets cloned later.
Only register repositories you trust, ideally ones you can read, and prefer naming a
specific commit or tag if the upstream accepts one.

### 4. `sudo` and the install path

`install.sh` and the base-environment installers add apt repositories and keys
(`repo.charm.sh` for `gum`; AMD's `repo.radeon.com` via the `amdgpu-install`
package), install the ROCm stack with `apt`, and build `librocdxg` from source with
`sudo`. Piping an installer straight into a shell (`curl … | bash`) means that code
runs without being read first. The toolkit
supports both, and documents the clone-and-run route as the recommended one. If you
care about the difference — and you should — read `install.sh` before running it.

### 5. Servers, ports and network exposure

The AI tools listen on a port and are reached from your Windows browser through
WSL2's localhost forwarding. Exposure depends on the tool:

- ComfyUI is launched with `--listen 127.0.0.1` (loopback only).
- **kohya_ss is launched with `--listen 0.0.0.0`**, and **Text Generation WebUI with
  `--listen`**, which binds all interfaces. If Windows Firewall allows the WSL port
  through, or you have configured port forwarding, those UIs are reachable from your
  LAN — and neither has authentication by default.
- The idle-hibernation wake page (`scripts/utils/wake_server.py`) also binds all
  interfaces. It serves a small static page and nothing else, but a stranger who can
  reach the port can wake — and therefore restart — your server repeatedly.
- Text Generation WebUI is started with `--trust-remote-code`, which executes Python
  shipped inside a model repository you load.

If you only ever use these tools on your own machine, leave the defaults alone. If
you change a port or a host binding, understand that you are the one widening the
exposure, and firewall it on the Windows side.

### 6. Windows-side artifacts

The toolkit writes `.bat` launchers into the Windows Desktop and reads values by
invoking `cmd.exe` (for example to find `%USERPROFILE%`). Anything that can write to
your Desktop can create one of those files; they are unsigned and will look like
exactly what any other shortcut-planting attack produces. Windows SmartScreen or your
antivirus flagging a freshly generated `.bat` that calls `wsl.exe` is not necessarily
a false positive.

---

## Out of scope

Please report these upstream rather than here:

- Vulnerabilities in **ROCm, `librocdxg`, the AMD Windows driver, PyTorch, Triton, or
  the AI tools themselves** (ComfyUI, SD.Next, Automatic1111, kohya_ss, Text
  Generation WebUI) or their dependencies. Use their own trackers.
- Anything that requires the attacker to **already have write access to your WSL user
  account or root**. At that point the toolkit's files are the least of your
  problems — such a report is only interesting if it *escalates* (for example,
  user-writable file → root, or WSL → Windows).
- **Your own configuration.** Registering a hostile repository, pasting a hostile
  `user.env`, or setting `HSA_OVERRIDE_GFX_VERSION` after being warned that it hides
  the GPU are user decisions, not vulnerabilities.
- Reports whose only content is a generic scanner finding in a third-party dependency
  with no path through this code.

## If something does go wrong

- Stop the tools and free the GPU: close the launcher windows, or stop the servers
  from the menu. Nothing in the toolkit keeps running in the background by itself
  except a tool you launched.
- Review `~/.config/rocm-wsl-ai/` — `user.env`, `gpu.env`, `perf.env` and
  `tools.local` are the files that get executed. Delete anything you did not write
  yourself.
- Rotate any token that was exported through `user.env`, since every launched tool
  inherited it.
- Then report it, with the config file, if the cause was something other than your
  own edits.
