# MouseQuickSwitch requirements

## Goal

A native macOS menu-bar utility for mapping one Logitech M585 side button to either Command-Tab application switching or activation of a selected application.

## Behavior

- Run without a Dock icon or Logitech software.
- Record a side button through a standard macOS `otherMouseDown` event and save its button number.
- Suppress the mapped button's original mouse action while mapping is enabled.
- Offer two mutually exclusive, persistent actions: send one Command-Tab shortcut, or activate/launch a selected `.app`.
- Keep selected-application mode as the default for existing users.
- Offer a standard application picker, an enable/pause control, permission guidance, and Quit.
- Migrate recorded button, mode, target, and enabled state from mouseQuick or MousePlus on first launch.
- Store preferences locally without network access or telemetry.

## Limits

- Use Apple frameworks and Swift only.
- Standard mouse events identify a button number, not a physical mouse. Another mouse with the same button number can trigger the mapping.
- Vendor-specific HID events and the M585 Easy-Switch device-selection button are outside scope.
- macOS Accessibility and potentially Input Monitoring permissions are required for event interception; posting Command-Tab also depends on system permission.

## Acceptance

1. Build and run MouseQuickSwitch.app on macOS.
2. Record the M585 side button and select Command-Tab mode. Consecutive presses alternate between the two recent applications.
3. Select application mode and a target `.app`. A press activates or launches that app.
4. The mapped button no longer performs its old Back/Forward action while mapping is enabled.
5. Pausing or quitting restores the button's normal behavior.
6. Relaunching restores the saved configuration.
