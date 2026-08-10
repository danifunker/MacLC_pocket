# misterdeploy

Reusable tooling to push and launch a [MiSTer](https://mister-devel.github.io/MkDocs_MiSTer/)
core through the **MiSTer Remote** web UI (the [mrext](https://github.com/wizzomafizzo/mrext)
HTTP/websocket API on port `8182`). Not specific to this project — host, port, ssh key,
core filename and folder are all flags/env, so it works for any core on any machine.

## `launch_unstable_core.py`

Pushes a core (optional), reboots the MiSTer for a clean menu, then drives the
**main-menu OSD** with generated keystrokes to select the core, and verifies what
launched.

The keystroke sequence is **generated at run time from the live menu listing**
(`POST /api/menu/view`), so a core dropped into the folder under any new filename is
found correctly — just pass `--core <filename>`. No menu position is hard-coded; the
downloader re-populating `_Unstable` simply recomputes on the next run.

> The on-screen OSD orders entries **case-insensitively** (`ao486` sorts among the
> `A`s; `MacLC` is the first `M`, before `MSX`). The API returns them case-*sensitively*,
> so the script re-sorts the filenames itself. A subfolder opens with the cursor on its
> `<UP-DIR>` row, so the core's row is its index + 1 (auto-derived from the `up` field).

### Usage

```bash
# Launch a core already on the MiSTer (host/port from env MISTER_HOST/MISTER_HTTP_PORT):
python launch_unstable_core.py --core MacLC.rbf

# Push a fresh build, then launch it (explicit host + ssh key):
python launch_unstable_core.py --host 192.168.1.50 --ssh-key ~/.ssh/mister \
    --push ./output_files/MacLC.rbf --core MacLC.rbf

# Preview the generated keystrokes without touching anything:
python launch_unstable_core.py --core MacLC.rbf --dry-run
```

### Options (all machine config is a flag or env var)

| flag | env | default | purpose |
|------|-----|---------|---------|
| `--host` | `MISTER_HOST` | `MiSTer.local` | hostname / IP |
| `--port` | `MISTER_HTTP_PORT` | `8182` | MiSTer Remote port |
| `--core` | `RBF_NAME` | — (required) | core filename to launch |
| `--folder` | `MISTER_CORE_FOLDER` | `_Unstable` | top-level `_` folder holding the core |
| `--push FILE` | — | off | scp `FILE` into the folder (md5-verified) first |
| `--ssh-key` | `MISTER_SSH_KEY` | — | ssh identity for `--push` |
| `--ssh-user` | `MISTER_SSH_USER` | `root` | ssh user for `--push` |
| `--no-reboot` | — | reboots | skip the clean-menu reboot |
| `--reboot-wait` | — | `180` | seconds to wait for the web service after reboot |
| `--delay` | — | `0.3` | seconds between key presses |
| `--updir-rows` | `MISTER_OSD_UPDIR_ROWS` | auto | override the `<UP-DIR>` row offset |
| `--no-verify` | — | verifies | skip the post-launch `coreRunning` check |
| `--max-tries` | — | `2` | reboot+select attempts; auto-retries if `coreRunning` misses (blind OSD nav is timing-sensitive) |
| `--dry-run` | — | off | print keystrokes; push/reboot/send nothing |
| `--seed-file FILE` | — | off | local file to seed a save image, **create-only-if-missing** |
| `--seed-remote PATH` | — | — | absolute remote path for `--seed-file` |
| `--seed-mount-cfg PATH` | — | — | absolute remote `.s<N>` mount-memory file to create-if-missing |
| `--seed-mount-rel REL` | — | — | relative path stored in the `.s<N>` file (e.g. `games/MACLC/MacLC.nvr`) |
| `--seed-mount-size N` | — | `1024` | size of the `.s<N>` file (NUL-padded; MiSTer uses 1024) |

**Seeding a save image (zero-touch NVRAM).** `--seed-*` drops a default save file and
pre-writes MiSTer's per-slot mount-memory (`config/<core>.s<N>`) so a save image is
auto-mounted from the first boot with no manual OSD mount. Both are **create-only-if-missing**,
so an existing (saved) file and the user's mount are never overwritten — only the core
itself is always re-pushed. Under git-bash, set `MSYS_NO_PATHCONV=1` so absolute
`/media/fat/...` args aren't rewritten to Windows paths.

Requires `scp`/`ssh` on `PATH` (for `--push`) and the `websockets` Python package.

In this repo, `scripts/deploy_screenshot.sh` is the MacLC wrapper: it verifies the
Quartus build, then calls this tool with values from `scripts/local.env`.
