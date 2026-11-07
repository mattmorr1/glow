# How Lid Glow controls the logo

These notes cover how the MacBook Pro with PROLED XDR drives its illuminated lid
logo, and how Lid Glow takes over that control. Everything was observed on
macOS 27.2 (build 26B8119) on a `Mac17,13`.

## The hardware

The IORegistry has a dedicated PWM device for the logo:

```
bklb-backlight@0  <class AppleARMPWMDevice>
  "pwm-frequency"  = 24000000      (24 MHz clock)
  "high-period"    = 32            (on ticks)
  "low-period"     = 928           (off ticks, period 960 = 25 kHz)
  "enabled"        = Yes
  "nits-to-pwm-percentage-part1" = 10, 20, 50, 100, 200, 500, 600, 1000 nits
  "nits-to-pwm-percentage-part2" = 1, 2, 5, 10, 20, 50, 60, 100 %
  "nits-to-pwm-calibration"      = per-device calibration points
```

Run `ioreg -r -n bklb-backlight -l` to see yours.

The private CoreBrightness framework owns the logo. It sets the level from the
screen brightness and the ambient light sensor, and it sends `set-duty-cycle`,
`set-enabled`, and `set-hz` to the PWM device through
`IORegistryEntrySetCFProperties`. Apple's
[off switch](https://support.apple.com/en-us/149248)
(`LEBacklightMode`) is a CoreBrightness preference.

## Writing the PWM directly

A regular user process can send the same properties. No sudo or entitlement is
needed:

| Request | Result |
| --- | --- |
| Lower duty than macOS chose | Holds until macOS next changes the level |
| Higher duty, up to 959/960 | Holds, no password needed |
| `set-duty-cycle` 0 | Rejected with `0xe00002c2` (bad argument) |
| `set-enabled` NO | Logo turns off; restoring the duty cycle turns it back on |

An instrumented write from inside a sandboxed development session returned
`0xe00002e2` (not permitted). The same write from a regular Terminal succeeded.

macOS only rewrites the PWM when its own target changes (screen brightness,
room light, sleep and wake). Lid Glow polls the PWM. When the value differs
from the last value Lid Glow wrote, macOS has picked a new level. Lid Glow
takes that as the new automatic level and applies the user's setting relative
to it.

## Tools in this repo

- `probe.m` queries CoreBrightness for logo-related properties. It makes no
  changes.

  ```sh
  clang -framework Foundation probe.m -o /tmp/macbook-logo-probe && /tmp/macbook-logo-probe
  ```

- `pwm-test.m` sets two lower duty cycles at a fixed screen brightness, checks
  that they hold, and restores the original level.

  ```sh
  clang -Wall -Wextra -Werror -fobjc-arc -framework Foundation -framework IOKit pwm-test.m -o ./pwm-test
  ./pwm-test --test
  ```
