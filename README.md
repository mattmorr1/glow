# Lid Glow

Control the glowing Apple logo on the new MacBook Pro with PROLED XDR. Dim it,
turn it off, push it past macOS's room-light limit, or animate it. It's a free,
open-source menu bar app.

<!-- Demo video: drag an .mp4 into this README on GitHub to embed it here. -->

- **Brightness:** from Off, through the automatic level, up to the hardware maximum
- **Max in any room:** macOS caps the logo in dim rooms; Lid Glow can go to full
  brightness without an admin password
- **Effects:** Steady, Breathing, Heartbeat, Beacon
- **Follows macOS:** your setting stays relative to macOS's automatic level as
  room light and screen brightness change
- **Low overhead:** about 0.1% CPU when steady and under 1% when animating.
  The app restores macOS's level on quit and sleep.

It only works on MacBook Pro models with the illuminated logo.

## Install

1. Download `Lid-Glow-*.zip` from
   [Releases](https://github.com/mattmorr1/applelogo/releases/latest).
2. Unzip it and move **Lid Glow** to Applications.
3. Open it. The glowing-lid icon appears in the menu bar.

If macOS says the app can't be opened, run this once in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/Lid Glow.app"
```

### Build from source

You need the Xcode Command Line Tools (`xcode-select --install`). No Apple
Developer account is required.

```sh
./build.sh
open "dist/Lid Glow.app"
```

## Use

Click the menu bar icon.

- **Slider:** the left end turns the logo off. The middle tick is macOS's
  automatic level. The right end is the hardware maximum.
- **Effect:** animates the logo up to the slider's level.
- **Automatic:** gives control back to macOS.
- **Open at login:** starts Lid Glow when you log in.

Lid Glow remembers your settings. To start an effect from Terminal, run:

```sh
"/Applications/Lid Glow.app/Contents/MacOS/LidGlow" --breathe
```

## How it works

Lid Glow writes the logo's PWM controller (`bklb-backlight`) directly through
IOKit, the same way macOS's CoreBrightness does.
[docs/RESEARCH.md](docs/RESEARCH.md) has the details.

## Caveats

- Lid Glow uses private, undocumented macOS interfaces. A macOS update could
  break it. If that happens, the app shows an error and leaves the logo to
  macOS.
- Verified on macOS 27.2 (26B8119).
- To keep the logo off without running any app, use Apple's
  [Terminal command](https://support.apple.com/en-us/149248).

Lid Glow is not made by or affiliated with Apple. MIT License.
