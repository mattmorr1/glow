# MacBook Logo Brightness

Exploring independent brightness control for the illuminated lid logo on the MacBook Pro with PROLED XDR.

macOS exposes an [off switch](https://support.apple.com/en-us/149248). The goal is to verify two distinct nonzero logo levels while keeping the built-in display at the same brightness. No working dimmer has been verified.

## Read-only probe

The probe loads the private CoreBrightness framework and queries its brightness client. The initial run on macOS 27.2 returned no values for the candidate logo properties. The probe does not change settings.

```sh
clang -framework Foundation probe.m -o /tmp/macbook-logo-probe
/tmp/macbook-logo-probe
```

The Mac's IORegistry exposes a dedicated PWM device named `bklb-backlight@0`. The private CoreBrightness framework contains a logo PWM control module. The next step is to verify whether the service exposes a usable control to a third-party process.
