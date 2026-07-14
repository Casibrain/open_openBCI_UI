# AGENTS.md — OpenBCI GUI

## What this is

Processing 4 (Java) desktop app for EEG data visualization. All source lives in `OpenBCI_GUI/` as `.pde` files — Processing compiles them to Java. There is no Gradle, Maven, or npm.

## Build

Requires Processing 4.2 installed at `/Applications/Processing42.app` (macOS) or equivalent.

```bash
# Copy bundled libraries to Processing's library directory (one-time or after library changes)
rtk mkdir -p ~/Documents/Processing/libraries/
rtk cp -a OpenBCI_GUI/libraries/. ~/Documents/Processing/libraries/

# Build release (must run from repo root)
rtk python release/build.py
```

Output: `application.macosx/`, `application.windows64/`, or `application.linux64/` depending on OS.

**Gotcha**: `processing-java` always exits with code 1 even on success — this is a known Processing bug (processing/processing#5468). The build script uses `subprocess.check_call` so it will raise on non-zero exit; CI works around this by using `subprocess.run` in the test step.

## Test

```bash
rtk python GuiUnitTests/run-unittests.py
```

Runs JUnit tests inside a Processing sketch. Copies specific `.pde` files from `OpenBCI_GUI/` into `GuiUnitTests/`, runs the sketch, then cleans up. Only works on macOS and Windows (Linux CI skips tests — requires a display).

Currently tested modules: `PacketLossTracker`, `TimeTrackingQueue`.

## Project structure

- `OpenBCI_GUI/` — all application source (`.pde` files)
  - `OpenBCI_GUI.pde` — main entry point, global variables, `setup()`/`draw()`
  - `Board*.pde` — hardware board abstractions (Cyton, Ganglion, BrainFlow, etc.)
  - `W_*.pde` — individual widgets (TimeSeries, FFT, Networking, etc.)
  - `WidgetManager.pde` — widget registry; add new widgets here
  - `W_Template.pde` — starting point for new widgets
  - `HeadPlotElectrodes.pde` — shared component for 10-20 electrode layout
  - `libraries/` — bundled Processing libraries (controlP5, grafica, LSL, minim, oscP5, etc.)
- `GuiUnitTests/` — unit test sketch
- `release/` — build/package scripts (`build.py`, `package.py`)
- `Networking-Test-Kit/` — test tools for UDP/OSC/LSL/Serial networking

## Key conventions

- **Branching**: PRs target `development`, not `master`. Branch off `development`.
- **Version string**: Defined in `OpenBCI_GUI.pde` line 65 as `localGUIVersionString`. The `build.py` script auto-updates `localGUIVersionDate` from the last git commit timestamp.
- **Widget pattern**: Subclass `Widget` (from `Widget.pde`), register in `WidgetManager.pde`'s `setupWidgets()`. See `W_Template.pde`.
- **Global state**: Heavy use of globals in `OpenBCI_GUI.pde`. Unit tests avoid copying `OpenBCI_GUI.pde` because its `setup()` conflicts with the test sketch.
- **Libraries**: Bundled in-repo under `OpenBCI_GUI/libraries/`. Do NOT use Processing's library manager — these are pinned versions.

## CI

Three platform workflows in `.github/workflows/`: `mac_build_deploy.yml`, `windows_build_deploy.yml`, `linux_build_deploy.yml`. All install Processing 4.2, copy libraries, build, and package. macOS and Windows also run unit tests. Deploy uploads to S3.

## Architecture

### Channel visibility system

- Global `boolean[] channelVisibility` array in `OpenBCI_GUI.pde` is the single source of truth
- All widgets iterate `nchan` and check `channelVisibility[i]` directly — no per-widget ChannelSelect
- `ChannelSelectorPopup` in `TopNav.pde` provides Swing JFrame-based head-plot UI for toggling visibility
- `HeadPlotElectrodes.pde` — reusable component for 10-20 electrode positions, used by both HeadPlot widget and ChannelSelectorPopup

### Hardware support

- `BoardCytonSerialDirect.pde` — Direct USB serial at 921600 baud, auto-detects 8/16/32 channels from packet size
- 32-channel maps to standard 10-20 order: Ch1=Fp1, Ch2=Fp2, ..., Ch32=O2

### Swing popups (not PApplet)

- PApplet windows create separate OpenGL contexts that crash when sharing with main window
- Use Swing JFrame with `Graphics2D` for popups requiring native window features (title bar, drag, resize)
- MouseListener must be on JPanel (content pane), not JFrame, to avoid coordinate offset from title bar
- Processing compiler does not recognize JFrame methods on typed variables — must recreate popup each time
