# MousePlus

A tiny macOS menu-bar app for mapping an M585 side button to an application. It uses Apple frameworks only and does not install a mouse driver.

See [requirements](REQUIREMENTS.md) for behavior and limits.

## Build

```sh
./scripts/build-app.sh
open .build/MousePlus.app
```

The build requires Xcode Command Line Tools or Xcode. On first launch, grant MousePlus Accessibility permission in System Settings → Privacy & Security → Accessibility, then restart MousePlus. If macOS also requests Input Monitoring permission, grant it and restart.

## Configure

1. Choose **Record Side Button** and click the M585 side button.
2. Choose **Select Application…** and pick an `.app`.
3. For ChatGPT.app, enable **Switch to Codex** to send Control-3 after launch.
4. Ensure **Mapping Enabled** is checked.

MousePlus saves settings in macOS user defaults. It has no network access or telemetry. It is a local prototype; button capture must be tested with the physical M585.
