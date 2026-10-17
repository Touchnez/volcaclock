# VolcaClock

A tiny macOS menu bar app that sends MIDI clock from djay Pro (or any Ableton Link app) to a Volca or any other MIDI gear.

djay Pro doesn't output MIDI clock, only Ableton Link. VolcaClock joins the Link session, follows the tempo and sends a standard MIDI clock (24 ppqn) to the MIDI output of your choice. Map a controller button: one press starts your machine on the next downbeat, another stops it. Latency offset adjustable in 5 ms steps. Negligible CPU load.

Tested with djay Pro, a Novation Launch Control 3 and a Korg Volca Kick.

## Download

Get the latest version from the [Releases](../../releases) page. Requires macOS 12 or later, Apple Silicon or Intel.

## Safety

VolcaClock only communicates with other Link apps on your local network: no internet connection, no data collection. The full source code is in this repository.

The app is not signed by Apple (no paid developer account), so macOS warns you on first launch. To open it: System Settings > Privacy & Security > "Open Anyway". Allow local network access if asked.

## Usage

1. Enable Ableton Link in djay Pro's settings.
2. Click the metronome icon in the menu bar: the first line shows the tempo and the number of Link peers.
3. Pick your MIDI output, then "Learn button..." and press the controller button you want to use.
4. Press it: the icon shows an hourglass (armed), then a play sign when your machine starts on the downbeat. Press again to stop.

The menu follows the macOS language: French on a French system, English everywhere else.

## Build from source

Requires Apple's command line tools (`xcode-select --install`). Then, in the project folder:

```
bash build.sh
```

The script downloads the Ableton Link SDK and builds `build/VolcaClock.app`. `bash release.sh` creates the distributable archives.

## License

GPL v2 or later, no warranty. Built on Ableton Link (GPL v2 or later) and asio (Boost license). Not affiliated with Korg, Novation, Ableton or Algoriddim.
