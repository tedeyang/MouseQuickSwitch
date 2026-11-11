# MousePlus requirements

## Goal

A small native macOS menu-bar utility that maps one configurable side button on a Logitech M585 to bringing a chosen application to the foreground. The initial use case is opening ChatGPT.app and switching to its Codex view.

## Version 1

- Run as a menu-bar app without a Dock icon or Logitech software.
- Record the mouse button by asking the user to click it. Support standard macOS `otherMouseDown` events and save the button number locally.
- Choose a target `.app` with a standard file picker and save its path locally.
- On a matching press, suppress the original mouse-button action and activate or launch the target app.
- Offer an optional “Switch to Codex” setting for ChatGPT.app, sending Control-3 after activation.
- Clearly show missing permissions and provide a way to request Accessibility access.
- Provide controls to enable or pause the mapping and quit the utility.
- Persist preferences across launches. Do not collect or transmit data.

## Constraints and limits

- Keep the source and build self-contained in this repository, using Apple frameworks and Swift only.
- The standard mouse-event approach identifies a button number, not an individual physical mouse. The same button number on another mouse would also trigger. If the M585 emits a vendor-specific HID event instead, that requires a separate implementation.
- The Easy-Switch device-selection button is outside the version 1 scope.
- Accessibility permission is required for intercepting and suppressing mouse events and sending the Codex shortcut.
- On this Mac, the installed desktop application is ChatGPT.app; an independently named Codex.app was not found.

## Acceptance

1. Build a runnable MousePlus.app on macOS.
2. Record a side button, choose ChatGPT.app, and press the button: ChatGPT becomes frontmost.
3. With “Switch to Codex” enabled, the app sends Control-3 after ChatGPT activates.
4. The mapped button no longer performs its previous Back/Forward action while MousePlus is active.
5. Quitting or pausing MousePlus restores the button's normal behavior.
6. Relaunching MousePlus restores the saved configuration.
