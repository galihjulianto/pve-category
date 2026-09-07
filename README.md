# pve-category

Group Proxmox VE's VM/CT resource tree into custom categories (by name, icon,
and ID ranges) via a config-driven patch to `pvemanagerlib.js` — with
validation, backups, rollback, and automatic reinstallation after Proxmox
package updates wipe the patch out.

## Why

Proxmox's default resource tree just lists every VM/CT flat, sorted by ID.
There's no built-in way to group them into folders like "infrastructure",
"monitoring", "databases", etc. This project patches the web UI's client-side
JS (`pvemanagerlib.js`) to add that grouping, driven entirely by a JSON
config file — no manual JS editing required after initial setup.

**The problem every UI-patching approach for Proxmox eventually hits:**
`pvemanagerlib.js` belongs to the `pve-manager` Debian package. Any time that
package is upgraded — even a minor point release, not just a major version
bump — dpkg overwrites the file with a stock copy, silently wiping any
patch. Most existing mods for Proxmox's UI (see "Prior art" below) either
don't address this at all, or note it as a known limitation requiring manual
reinstallation.

This project solves that with an apt hook: `pve-category ensure` is an
idempotent command that detects when hooks have gone missing and
reinstalls them automatically, and it's wired up to run right after any
`pve-manager` package update via `DPkg::Post-Invoke` — no manual intervention
needed.

## Features

- **Config-driven**: categories, icons, order, and VM/CT ID ranges live in
  `/root/pve-ui-categories.json`. No JS knowledge needed to add a category.
- **Anchor-based patching with syntax validation**: the script locates known
  code anchors in `pvemanagerlib.js`, and validates the generated file with
  `node --check` before writing anything to disk. If an anchor doesn't match
  (e.g. a Proxmox version changed that function's shape), it aborts cleanly
  instead of writing a broken file.
- **Full command set**: `install`, `apply`, `status`, `rollback`, `ensure`.
- **Backups**: a pristine (pre-install) backup is kept, plus a timestamped
  backup before every write, so you can always get back to a known state.
- **Automatic recovery from package upgrades**: an apt `Post-Invoke` hook
  detects when `pve-manager` was part of the current dpkg transaction and
  re-applies the hooks afterward, automatically.

## Requirements

- Proxmox VE 9.x (developed and tested against `pve-manager` 9.2.11 — see
  [Compatibility](#compatibility) below for other versions)
- Root access
- `node` available on the host (used for `node --check` syntax validation)

## Install

```bash
git clone https://github.com/galihjulianto/pve-category.git
cd pve-category
./install.sh
```

This copies:
- `pve-category` → `/usr/local/sbin/pve-category`
- `apt-hook/pve-category-apt-check.sh` → `/usr/local/sbin/`
- `apt-hook/99-pve-category` → `/etc/apt/apt.conf.d/`

Use `./install.sh --no-hook` to skip the apt auto-reinstall hook if you'd
rather reinstall manually after upgrades.

Then set up your config and apply the patch:

```bash
cp config/pve-ui-categories.example.json /root/pve-ui-categories.json
$EDITOR /root/pve-ui-categories.json    # define your own categories/ranges/ids
pve-category install
pve-category status                     # confirm hooks are active
```

## Usage

```
pve-category install    # first-time patch of pvemanagerlib.js
pve-category apply      # re-generate the category block from config
                         #   after you've edited the JSON, without a full reinstall
pve-category status      # show whether hooks are installed + current config
pve-category rollback   # restore the file to its pre-install (stock) state
pve-category ensure     # idempotent: reinstall hooks only if missing
                         #   (this is what the apt hook calls automatically)
```

## Config format

```json
{
  "main services": {
    "order": 1,
    "icon": "fa fa-server",
    "ids": [],
    "ranges": [[100, 199]]
  },
  "experimental": {
    "order": 6,
    "icon": "fa fa-flask",
    "ids": [101, 250],
    "ranges": [[900, 999]]
  }
}
```

- `order` — display order in the tree.
- `icon` — a Font Awesome class string used in the UI.
- `ranges` — inclusive `[start, end]` VMID ranges assigned to this category.
- `ids` — specific VMIDs to include outside of any range.

Overlaps between categories (same VMID matched by more than one) are
detected and reported at `apply`/`install` time.

## How the auto-reinstall hook works

`pvemanagerlib.js` gets overwritten in full whenever the `pve-manager`
package is upgraded — this happens on essentially every point release, not
just major version jumps. To handle this without manual intervention:

1. **`DPkg::Pre-Install-Pkgs`** runs `pve-category-apt-check.sh --mark`,
   which reads the list of packages in the *current* dpkg transaction (fed
   via stdin) and drops a flag file if `pve-manager` is among them. This
   runs *before* the new files are unpacked.
2. **`DPkg::Post-Invoke`** runs `pve-category-apt-check.sh --run-if-marked`,
   which checks for that flag file *after* the transaction (and file
   unpacking) is complete, and if present, calls `pve-category ensure` and
   clears the flag.

This two-phase split exists because `Pre-Install-Pkgs` is the only reliable
place to see which packages are in the current transaction, but it fires
too early to patch the new file; `Post-Invoke` fires at the right time but
can't tell you which packages were just processed. The flag file bridges
the two.

`ensure` itself never fails loudly for conditions that are actually fine —
hooks already present, pve-category never configured on this host, etc. —
so a `pve-manager` upgrade never gets reported as failed by apt/dpkg because
of this hook.

## Compatibility

Tested against `pve-manager` 9.2.11. The script matches on literal code
anchors inside `pvemanagerlib.js` (specific function signatures like
`groupChild()`, `nodeSortFn()`, and a `selectionchange` listener). If a
Proxmox version changes the shape of that code, `install`/`apply`/`ensure`
will detect the mismatch and abort **without writing anything to disk** —
they don't silently corrupt the file. If you hit this on a different
version, please open an issue with your `pve-manager` version so the
anchors can be updated.

## Prior art

Patching `pvemanagerlib.js` to customize the Proxmox UI isn't a new idea —
a few other projects and gists take a similar approach for different goals:

- [Meliox/PVE-mods](https://github.com/Meliox/PVE-mods) — adds sensor
  temperature readings to the node summary view. Explicitly notes that
  Proxmox upgrades may overwrite the mod and require manual reinstallation.
- Various one-off gists patch things like VM/CT sort order, UI width, or
  NIC emulation options, typically via a single `sed`/diff applied once.

What's different here: a config-driven category system (rather than a
single hardcoded tweak), anchor validation plus `node --check` before any
write, a full install/apply/status/rollback/ensure command set with
backups, and — the main gap this project fills — automatic reinstallation
after package upgrades via an apt hook, rather than a manual, easy-to-forget
step.

## License

MIT (or pick whatever you prefer before publishing)

## Disclaimer

This patches an internal, undocumented file that's part of Proxmox VE
itself, not a supported extension point. It's validated with syntax
checking and anchor matching before every write, and full backups are kept,
but you're still modifying vendor-owned files. Use at your own risk, and
test on a non-production node first if you can.
