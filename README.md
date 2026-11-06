# TouchbarControl

TouchbarControl is a macOS menu bar app that turns a MacBook Touch Bar on and off.

The app lives in the menu bar, not the Dock. Click the keyboard icon to open it.

## What it does

- **On** leaves the Touch Bar working as usual.
- **Off** covers the Touch Bar, including the Escape key, with a black layer. The keys do not respond.
- While it is off, hold **Fn** to show the function keys. Releasing Fn covers the bar again.
- **Double-tap Shift** toggles the Touch Bar from any app.
- When the screensaver starts or the display sleeps, the Touch Bar turns off. It turns back on after you leave the screensaver or wake the Mac, if it was on before. A Touch Bar you turned off yourself stays off.
- Quitting the app restores the normal Touch Bar. The on/off choice is remembered the next time you open it.

The black cover only stays in place while TouchbarControl is running.

## Shortcut permission

Double-tap Shift works in other apps after you allow TouchbarControl in **System Settings → Privacy & Security → Accessibility**. If the shortcut does not respond, open the menu and choose **Allow**.

## Requirements

- A Mac with a Touch Bar
- macOS 26.5 or later

## Build

Open `touchbarcontrol.xcodeproj` in Xcode and run the `touchbarcontrol` scheme. The built app is named **TouchbarControl**.
