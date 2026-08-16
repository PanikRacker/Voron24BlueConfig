# Voron 2.4 "Blue" — Klipper config

This repo **is** the printer's config directory. On the printer it lives at
`/home/voron24blue/printer_data/config/`, and every absolute path inside `.cfg`/`.sh`
files assumes that location. Editing happens here (Windows), deployment happens by
pulling on the Pi — see *Deployment*.

## Hardware

| | |
|---|---|
| Frame | Voron 2.4, 300×300 (`position_max: 300` on X/Y) |
| MCU | BTT Octopus V1, STM32F446, 32KiB bootloader, 12MHz crystal |
| Kinematics | CoreXY, 500 mm/s / 5000 mm/s² |
| Extruder | Clockwork/Bondtech 5mm gears, `rotation_distance: 22.983767`, PT1000 |
| Probe | Klicky (dockable) + `[z_calibration]` (nozzle-on-endstop auto Z offset) |
| Extras | Nevermore filter, Stealthburner LEDs, filament runout+insert sensors, Spoolman, Telegram bot, timelapse |

## Include structure

`printer.cfg` holds only `[mcu]`, `[printer]` and pulls in:

- `printer_includes.cfg` — one `[include]` line per hardware/feature directory
- `printer_features.cfg` — small global Klipper features (`[gcode_arcs]`, `[save_variables]`)

Two include styles are used deliberately:

- `Dir/*.cfg` — everything in the directory is active
- `Dir/_.cfg` — the directory has an **`_.cfg` switchboard**; that file lists the
  individual includes and commented-out lines are the *off* switch.
  Used by `Fans/`, `Probe/`, `Macros/` (and nested `Macros/Helper/`, `Macros/Parking/`).

So to enable/disable a feature, comment its line in the relevant `_.cfg` — do not
delete files. Example: `Fans/_.cfg` currently selects the Noctua variant of dynamic fan
control and leaves `situational_fan_control.cfg` off.

`Macros/` is included as `Macros/*.cfg`, which resolves to just `Macros/_.cfg`, which in
turn includes the subdirectories. Adding a loose `.cfg` directly under `Macros/` would
silently be picked up too — put new macros in a subdirectory.

## Conventions

- **`UPPERCASE` macros are the user/slicer-facing API** (`PRINT_START`, `PARK`, `NEVERMORE`).
  **`_UNDERSCORE_PREFIXED` macros are internal** and should not be called from a slicer or
  the console. Keep that split when adding macros.
- Klicky's vendored files use its own `_PascalCase`/`_snake_case` names — that's upstream
  style, not this repo's.
- **Logging goes through `Macros/Helper/logger.cfg`**, never raw `action_respond_info`:
  - `_DEBUG MSG="..."` — normal operational messages
  - `_VERBOSE MSG="..."` — chatty/low-value messages
  - both respect the persisted `logger_mode` (0 none / 1 all / 2 debug / 3 verbose,
    set via `SET_LOG_MODE MODE=n`), and take an optional `TIME=` for "X in N seconds".
- **Persistent state uses `[save_variables]`** (`~/printer_data/.variables.stb`), read as
  `printer.save_variables.variables.<name>`. Initialize new variables from a
  `[delayed_gcode ..._INIT]` with `initial_duration: 1` guarded by an `if "<name>" not in ...`
  check — see `logger.cfg`. `VARIABLES_DISPLAY` / `VARIABLES_RESET` inspect and clear them.
- **Parameters**: always `{% set x = params.X | default(...) | int %}`-style with an explicit
  default and cast. Dispatch macros like `PARK` accept several spellings of a location
  (`back-low`, `back_low`, `bl`, …) — follow that when extending.
- **Guard conditionals** use `printer.idle_timeout.state != "Printing"` for
  "don't do this mid-print" and `printer.toolhead.homed_axes` for homing state
  (`CG28`/`CG32` are the conditional home/QGL wrappers — prefer them over bare `G28`/`G32`).
- LED status is set with `_status_*` macros (`_status_homing`, `_status_printing`, …).

## Shell commands

Several macros shell out via `[gcode_shell_command]` (needs the `gcode_shell_command`
Klipper extension installed on the printer):

| Script | Driver macro |
|---|---|
| `Backup/autocommit.sh` | `CONFIG_BACKUP` — auto-commits+pushes config, skipped while printing |
| `Macros/Helper/Git/*.sh` | `GIT CMD=...`, `_GIT_PULL`, `_GIT_STATUS`, `_GIT_RESET_HEAD` |
| `Webcam/timelapse_cleanup_*.sh` | `_TIMELAPSE_CLEANUP_*` |
| `Macros/Helper/*/variables_*.sh` | `VARIABLES_DISPLAY`, `VARIABLES_RESET` |

When touching these: the `command:` line is an **absolute path** and must be updated if a
file moves; scripts must stay **LF-terminated and executable** (a Windows CRLF checkout
breaks `#!/bin/bash`); and `timeout:` must exceed the script's real runtime.

## Deployment / workflow

The printer pulls this repo — there is no push-to-printer step from Windows:

1. Commit and push here.
2. On the printer run `CONFIG_UPDATE CONFIRM=true` (add `FORCE=true` to hard-reset local
   changes first). It runs `_GIT_PULL` then `FIRMWARE_RESTART` after 5s.
3. `CONFIG_BACKUP` runs the reverse direction — commits changes made through Mainsail.

Because of that, expect the printer's working tree to have its own commits; pull before
editing to avoid divergence.

**Nothing in this repo can be validated locally** — no Klipper, no Python, no test suite.
Correctness checks are limited to reading the config; the real check is
`FIRMWARE_RESTART` on the printer. Be conservative with edits that affect motion or
heating, and say plainly when a change is unverified.

## Non-Klipper files

`moonraker.conf` → `Moonraker/*.conf` (same switchboard idea), plus `KlipperScreen.conf`,
`crowsnest.conf`, `telegram.conf`, and `Spoolman/docker-compose.yml`. These are read by
their own daemons, not Klipper.

`secrets.conf` (Telegram tokens etc.) is **gitignored — never commit it or inline its
values**. Also gitignored: `Spoolman/data/`, ADXL result CSV/tarballs, `*.bkp`.

## Don't touch

`Probe/Klicky/` is vendored upstream (klicky-probe). Local customizations belong in
`Probe/klicky_probe.cfg`, and renames/overrides in `Probe/Klicky/klicky-macros-rename.cfg`
— keep the rest pristine so upstream updates stay mergeable.
