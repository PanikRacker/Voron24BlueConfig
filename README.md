# Voron 2.4 "Blue" — Klipper Configuration

[![Klipper](https://img.shields.io/badge/Klipper-firmware-red)](https://www.klipper3d.org/)
[![Voron](https://img.shields.io/badge/Voron-2.4%20%7C%20300mm-e0004d)](https://vorondesign.com/voron2.4)
[![MCU](https://img.shields.io/badge/MCU-BTT%20Octopus%20V1-blue)](https://github.com/bigtreetech/BIGTREETECH-OCTOPUS-V1.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

The complete Klipper config for my Voron 2.4 300×300, split into one directory per
subsystem and driven by a set of macros that try to make the printer behave like an
appliance: it heat-soaks itself, cleans its own nozzle, tracks its air filter's remaining
life, dims the lights when it starts printing, and powers itself off when it's done.

This repository **is** the printer's config directory — on the machine it lives at
`/home/voron24blue/printer_data/config/`, and the printer pulls updates from here.

> [!NOTE]
> This is a personal config, not a distribution. Pins, serial IDs, absolute paths, PID
> values and Z offsets are specific to my machine. Read before you copy — and never copy
> `Stepper/`, `Extruder/` or `Probe/` values blindly.

---

## Table of contents

- [Hardware](#hardware)
- [Highlights](#highlights)
- [Repository layout](#repository-layout)
- [How the includes work](#how-the-includes-work)
- [Macro reference](#macro-reference)
- [Conventions](#conventions)
- [Deployment workflow](#deployment-workflow)
- [Requirements](#requirements)
- [Credits](#credits)
- [License](#license)

---

## Hardware

|                |                                                                                  |
| -------------- | -------------------------------------------------------------------------------- |
| **Frame**      | Voron 2.4, 300 × 300 × 300                                                        |
| **Kinematics** | CoreXY — 500 mm/s, 5000 mm/s², SCV 5.0                                            |
| **MCU**        | BigTreeTech Octopus V1 (STM32F446, 32 KiB bootloader, 12 MHz crystal)              |
| **Drivers**    | TMC2209 / UART, quad Z (`quad_gantry_level`)                                       |
| **Toolhead**   | Stealthburner + Clockwork, Bondtech 5 mm gears, PT1000 hotend thermistor            |
| **Probe**      | [Klicky](https://github.com/jlas1/Klicky-Probe) dockable probe + `[z_calibration]`  |
| **Display**    | BTT Mini12864 with NeoPixel backlight                                              |
| **Chamber**    | Semitec 104NT chamber sensor, [Nevermore](https://github.com/nevermore3d/Nevermore_Micro) carbon filter |
| **Sensors**    | Filament runout **and** insert switches, ADXL345 for input shaper                  |
| **Extras**     | Spoolman, Moonraker-Telegram-Bot, Timelapse, Crowsnest, Tasmota smart plug          |
| **Tuning**     | Input shaper: X `mzv` @ 54.2 Hz, Y `2hump_ei` @ 55.4 Hz                            |

## Highlights

**A print start sequence that actually prepares the printer**
`PRINT_START` remembers the last filename in persistent storage, so a reprint of the same
file skips re-meshing. It preheats to 75 % of target while homing and quad-gantry-levelling,
runs Z calibration against the nozzle-on-endstop routine, loads or generates an adaptive bed
mesh, purges and scrubs the nozzle hot, spins up the Nevermore on an interval cycle, dims
the chamber lights and starts the timelapse — all with LED status feedback per stage.

**Interruptible heat soaking**
`HEAT_SOAK` waits for a temperature sensor to reach *thermal equilibrium* rather than a
fixed timer: it watches the smoothed rate of change (°C/min) and calls it done when the
chamber stops climbing. It can be cancelled, stopped and resumed, and it hands off cleanly
into a print (`HEAT_SOAK_RESUME`).

**Filter maintenance tracking**
The Nevermore's remaining filter hours are counted down across prints in persistent
variables. `NEVERMORE_STATUS` reports the filter condition as a percentage;
`NEVERMORE_SET_MAINTENANCE` sets the service interval and `NEVERMORE_RESET` zeroes the
counter after a cartridge change.

**One parking macro, many spellings**
`PARK LOCATION=back-low` — or `back_low`, `backl`, `bl`. Locations cover `bed`, `center`,
`front`, `back`, `purge`, `pause`, `warmup`, `print-end` and `change-nozzle`, each defined
in its own file under [Macros/Parking/Locations](Macros/Parking/Locations). Parking is
refused mid-print unless the printer is paused.

**Structured, switchable logging**
Nothing calls `action_respond_info` directly. Everything goes through
[`logger.cfg`](Macros/Helper/logger.cfg) as `_DEBUG` or `_VERBOSE`, filtered by a persisted
log mode (`SET_LOG_MODE MODE=0..3`), with optional countdown formatting for
"X in N seconds" messages.

**Git-based deployment, from the printer's console**
`CONFIG_UPDATE CONFIRM=true` pulls this repo on the Pi and firmware-restarts.
`CONFIG_BACKUP` commits and pushes changes made through Mainsail back here — and skips
itself while a print is running.

**Unattended finishing**
Runout pauses the print, turns the lights on and arms a cancel timer (1 h, or 8 h if a
filament change is expected). `POWER_OFF` cuts the printer via a Tasmota plug after a
delay, and can be armed or disabled per print.

## Repository layout

```
printer.cfg                 [mcu] + [printer] only — everything else is included
├── printer_includes.cfg    one include per subsystem directory
└── printer_features.cfg    small global features ([gcode_arcs], [save_variables])

Backup/            autocommit.sh + CONFIG_BACKUP driver
Bed/               bed heater, bed mesh, adaptive bed mesh
Display/           Mini12864 + NeoPixel backlight
Extruder/          Clockwork / Bondtech, PT1000
Fans/              part cooling, hotend, CPU/host temperature fans   [switchboard]
Filament_Sensor/   runout + insert switches and their handlers
Input_Shaper/      ADXL345 setup and resonance results
Lights/            Stealthburner LEDs, chamber daylight, LIGHTSWITCH
Macros/            all G-code macros                                  [switchboard]
│   ├── G_Commands/       CG28 / CG32 / FG28 / G32 conditional wrappers
│   ├── Heat_Soaking/     interruptible heat soak state machine
│   ├── Helper/           logger, SEARCH, M109/M190 overrides, git, save_variables tools
│   ├── Parking/          PARK dispatcher + one file per location
│   ├── Printing/         PRINT_START / PRINT_END / warmup / closure
│   └── Routines/         QGL, Z calibration, nozzle scrub, filament change, TEST_SPEED
Moonraker/         moonraker.conf split per topic
Nevermore/         filter fans, run-time tracking, display controls
Power/             idle timeout, Tasmota power-off
Probe/             Klicky (vendored) + local customizations           [switchboard]
Sensors/           chamber thermistor, homing_heaters
Spoolman/          active-spool macros + docker-compose for the server
Stepper/           X/Y/Z steppers, homing, auto Z calibration
Webcam/            timelapse + retention cleanup scripts
```

Non-Klipper files read by their own daemons: `moonraker.conf`, `KlipperScreen.conf`,
`crowsnest.conf`, `telegram.conf`, `mainsail.cfg`.

## How the includes work

Two include styles are used deliberately:

| Style        | Meaning                                                                    |
| ------------ | -------------------------------------------------------------------------- |
| `Dir/*.cfg`  | everything in the directory is active                                       |
| `Dir/_.cfg`  | the directory has a **switchboard**; that file lists the individual includes |

In a switchboard directory, a commented-out line is the *off* switch — features are
disabled by commenting, never by deleting files. For example
[`Fans/_.cfg`](Fans/_.cfg) selects the Noctua variant of dynamic fan control and leaves the
generic and situational variants off:

```ini
#[include dynamic_fan_control.cfg]
[include dynamic_fan_control_noctua.cfg]
[include fan_control.cfg]
#[include situational_fan_control.cfg]
```

Same idea in [`Probe/_.cfg`](Probe/_.cfg), where the inductive probe sits disabled next to
the active Klicky setup, and in `Moonraker/` for the daemon config.

## Macro reference

Uppercase macros are the user- and slicer-facing API. Underscore-prefixed macros are
internal and should not be called from a slicer or the console.

### Printing

| Macro                                        | Purpose                                                     |
| -------------------------------------------- | ----------------------------------------------------------- |
| `PRINT_START EXTRUDER_TEMP= BED_TEMP= [BED_MESH=] [SIZE=]` | full start sequence (see above)                |
| `PRINT_END`                                  | retract, park, heaters off, then hand off to `PRINT_CLOSURE`  |
| *(automatic)* `PRINT_CLOSURE`                | clears the mesh, fades the lights down over 3 min, runs the filter on for 10 min, renders the timelapse, powers off after 15 min |
| `PRINT_WARMUP`                               | preheat + heat soak before a print                          |
| `PRINT_SETTINGS FILAMENT_CHANGE=true`        | flags a planned filament change for this print               |
| `PAUSE` / `RESUME` / `CANCEL_PRINT` / `M600` | pause-resume handling with Klicky-safe parking               |
| `FILAMENT_CHANGE` / `FILAMENT_LOAD` / `FILAMENT_UNLOAD` | filament handling                                 |

### Motion, levelling and probing

| Macro                              | Purpose                                             |
| ---------------------------------- | --------------------------------------------------- |
| `CG28` / `FG28`                    | conditional home / forced home                       |
| `G32` / `CG32` / `CQGL`            | home + QGL + Z calibrate; `C*` variants skip if already done |
| `QUAD_GANTRY_LEVEL`                | Klicky-aware QGL                                     |
| `PROBE_ATTACH` / `PROBE_DOCK`      | Klicky dock handling                                 |
| `PROBE_CALIBRATE` / `PROBE_ACCURACY` | probe calibration wrappers                         |
| `BED_MESH_CALIBRATE` / `ADAPTIVE_BED_MESH` | adaptive meshing (`BED_MESH_FORCE`, `BED_MESH_SKIP`) |
| `NOZZLE_PREPARE` / `NOZZLE_CHANGE` / `clean_nozzle` | hot purge + brush routines           |
| `TEST_SPEED`                       | speed / acceleration stress test                      |

### Chamber, lights and power

| Macro                                                | Purpose                                  |
| ---------------------------------------------------- | ---------------------------------------- |
| `HEAT_SOAK` / `_START` / `_STOP` / `_CANCEL` / `_RESUME` | equilibrium-based heat soaking        |
| `NEVERMORE [SPEED=] [INTERVAL=] [CYCLE=] [DURATION=]` | filter fan with duty cycling             |
| `NEVERMORE_STATUS` / `_RESET` / `_SET_MAINTENANCE` / `_SET_CONDITION` / `_PAUSE` / `_OFF` | filter life tracking |
| `LIGHTSWITCH_ON` / `_OFF` / `_DIM` / `_LOCK`         | chamber lighting with delays and locking |
| `HEADLIGHT`, `SWITCH_ON_DAYLIGHT`, `SWITCH_OFF_DAYLIGHT` | individual light groups              |
| `POWER_OFF [DELAY=] [FORCE=]`, `POWER_OFF_ENABLE/DISABLE` | Tasmota plug + Pi shutdown           |

### Housekeeping

| Macro                                       | Purpose                                        |
| ------------------------------------------- | ---------------------------------------------- |
| `PARK LOCATION=<name>`                      | move the toolhead to a named position           |
| `SET_LOG_MODE MODE=0..3`                    | 0 none / 1 all / 2 debug / 3 verbose            |
| `SEARCH TERM=<string>`                      | grep the live `printer` object tree             |
| `VARIABLES_DISPLAY` / `VARIABLES_RESET`     | inspect / clear persistent variables            |
| `CONFIG_UPDATE CONFIRM=true [FORCE=true]`   | pull this repo on the printer, then restart      |
| `CONFIG_BACKUP`                             | commit + push printer-side changes               |
| `GIT CMD=<...>`                             | raw git access from the console                  |
| `TIMELAPSE_*`                               | timelapse control and retention cleanup          |
| `CLEAR_ACTIVE_SPOOL`                        | Spoolman integration                             |

## Conventions

- **Naming** — `UPPERCASE` is public API, `_UNDERSCORE` is internal. Klicky's vendored
  files keep their upstream `_PascalCase` style.
- **Logging** — `_DEBUG MSG="…"` for operational messages, `_VERBOSE MSG="…"` for chatty
  ones, both with an optional `TIME=` for countdowns. Never raw `action_respond_info`.
- **Persistent state** — `[save_variables]` in `~/printer_data/.variables.stb`, read via
  `printer.save_variables.variables.<name>`. New variables are initialized from a
  `[delayed_gcode …_INIT]` with `initial_duration: 1`, guarded by an
  `if "<name>" not in …` check.
- **Parameters** — always `{% set x = params.X | default(…) | int %}` with an explicit
  default and cast.
- **Guards** — `printer.idle_timeout.state != "Printing"` for "not mid-print",
  `printer.toolhead.homed_axes` for homing state. Prefer `CG28`/`CG32` over bare
  `G28`/`G32`.
- **LED status** — set through `_status_*` macros (`_status_homing`, `_status_printing`, …).
- **Shell scripts** must stay LF-terminated and executable; `[gcode_shell_command]`
  `command:` lines use absolute paths and must be updated when a file moves.

## Deployment workflow

The printer pulls — there is no push-to-printer step.

```bash
git add -A && git commit -m "…" && git push
```

Then, on the printer's console:

```
CONFIG_UPDATE CONFIRM=true
```

That runs `_GIT_PULL` and firmware-restarts after 5 seconds. Add `FORCE=true` to hard-reset
local changes first. Changes made through Mainsail travel the other way with
`CONFIG_BACKUP`, which commits and pushes them here — so expect the printer to have its own
commits, and pull before editing.

> [!IMPORTANT]
> Nothing here can be validated on a workstation — there is no Klipper, no test suite. The
> real check is `FIRMWARE_RESTART` on the printer. Be conservative with anything touching
> motion or heating.

## Requirements

Beyond a stock Klipper + Moonraker install:

- [`gcode_shell_command`](https://github.com/dw-0/kiauh) extension — required by the git,
  backup, timelapse-cleanup and power-off macros
- [`klipper_z_calibration`](https://github.com/protoloft/klipper_z_calibration) —
  nozzle-on-endstop automatic Z offset
- [`moonraker-timelapse`](https://github.com/mainsail-crew/moonraker-timelapse)
- [Spoolman](https://github.com/Donkie/Spoolman) — `Spoolman/docker-compose.yml` included
- [moonraker-telegram-bot](https://github.com/nlef/moonraker-telegram-bot)

`secrets.conf` (Telegram tokens and similar) is **gitignored** and must be created on the
printer by hand. Also gitignored: `Spoolman/data/`, ADXL result files, `*.bkp`.

## Credits

Standing on plenty of shoulders:

- [Voron Design](https://vorondesign.com/) and the stock Voron 2.4 config
- [Klicky Probe](https://github.com/jlas1/Klicky-Probe) by jlas1 — vendored in
  `Probe/Klicky/`, kept pristine so upstream updates stay mergeable
- [Adaptive bed mesh](https://github.com/Frix-x/klipper-voron-V2) by Frix_x
- [Interruptible heat soak](https://klipper.discourse.group/t/interruptible-heat-soak/1552)
  by blalor
- [Stealthburner LEDs](https://github.com/VoronDesign/Voron-Stealthburner) and
  [`TEST_SPEED`](https://github.com/AndrewEllis93/Print-Tuning-Guide) by Ellis

## License

[MIT](LICENSE) © Andreas Lohoff
