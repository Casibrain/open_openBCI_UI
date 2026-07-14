# CONTEXT.md — Development Context

## Current State

OpenBCI GUI v6 — Processing 4.2 desktop app for EEG visualization. Supports 8/16/32-channel Cyton hardware via direct USB serial connection at 921600 baud.

## Key Architecture

### Data Flow
```
Serial Port → BoardCytonSerialDirect → pendingDataQueue → getNewDataInternal()
  → Board.update() → accumulatedData → processNewData() → dataProcessingRawBuffer
  → DataProcessing → dataProcessingFilteredBuffer → Widget display
```

### Channel Visibility
- `boolean[] channelVisibility` in `OpenBCI_GUI.pde` — single source of truth
- `HeadPlotElectrodes.pde` — shared electrode layout component
- `ChannelSelectorPopup` in `TopNav.pde` — Swing JFrame popup for toggling visibility
- All 6 main widgets (TimeSeries, FFT, Focus, BandPower, EMG, Spectrogram) read directly from `channelVisibility[]`

### Hardware Auto-Detection
- `BoardCytonSerialDirect` reads first 3+ packets to determine channel count
- Packet format: 1(start) + 1(counter) + N×3(EEG) + 6(AUX) + 1(end) = 9 + N×3 bytes
- Valid sizes: 8ch=33, 16ch=57, 32ch=105 bytes

## Build Commands

```bash
rtk mkdir -p ~/Documents/Processing/libraries/
rtk cp -a OpenBCI_GUI/libraries/. ~/Documents/Processing/libraries/
rtk python release/build.py
```

## Testing

```bash
rtk python GuiUnitTests/run-unittests.py
```

## Known Gotchas

- `processing-java` exits with code 1 even on success (Processing bug #5468)
- Processing 4.2 required (4.5.5 has incompatible directory structure)
- Swing JFrame popups must recreate each time — Processing compiler doesn't recognize JFrame methods on typed variables
- MouseListener on JPanel, not JFrame — avoids title bar coordinate offset
- Wildcard `import java.awt.*` conflicts with Processing built-in classes
