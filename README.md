# Charging Limiter

A native, Apple Silicon-only macOS menu-bar utility that maintains a configurable
50–100% battery limit and sends a notification when the battery crosses above it.

This repository is a personal/local v1. It is not App Store software and it has
not been notarized. Charging control uses undocumented AppleSMC keys and a
root LaunchDaemon, so read the safety notes before enabling the helper.

## What it does

- Defaults to an enabled 80% limit, adjustable in 1% steps from 50% to 100%.
- Actively discharges to the selected limit when awake with the lid open.
- Restores adapter power at the target while keeping battery charging inhibited.
- Resumes charging below a 5% hysteresis window.
- Falls back to adapter power with charging inhibited during sleep or clamshell use.
- Keeps over-limit notifications active when the limiter toggle is off.
- Starts the privileged controller at boot and the menu-bar app at login.

There are no analytics, network calls, profiles, calibration features, or update
checks.

## Requirements

- Apple Silicon Mac
- macOS 13 or later
- Full Xcode (Command Line Tools alone can compile the Swift package but cannot
  build, sign, or test the `.app` and privileged helper bundle)
- A local Apple Development signing identity is recommended so macOS can retain
  a stable identity for the app and its helper

## Build and run

1. Install Xcode and select it:

   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```

2. Open `ChargingLimiter.xcodeproj`. In Signing & Capabilities, select the same
   development team for **Charging Limiter** and **ChargingLimiterDaemon**.

3. Build with Xcode or run:

   ```sh
   ./Scripts/build.sh
   ```

4. Copy `.build/xcode/Build/Products/Debug/Charging Limiter.app` to
   `/Applications` before opening it. Keeping a registered background item at a
   stable path avoids a broken helper registration after build-folder cleanup.

5. Open the app, allow notifications, and approve Charging Limiter under
   **System Settings → General → Login Items & Extensions → Allow in Background**.

6. In **System Settings → Battery**, turn off Apple's Charge Limit and Optimized
   Battery Charging so two controllers do not compete for charging state.

The helper persists `/Library/Application Support/ChargingLimiter/config.plist`
as a root-owned `0600` binary property list.

## Remove safely

Choose **More → Remove Background Helper** before deleting the app. The app asks
the daemon to restore adapter input and normal charging, unregisters the
LaunchDaemon, and then disconnects from it. After that, quit and delete the app.

If the menu app cannot contact the helper, do not manually delete the app until
you have confirmed macOS reports normal charging and adapter operation.

## Architecture

- `ChargingLimiterCore`: value types, notification episode tracking, and the pure
  limiter state machine.
- `ChargingLimiterSystem`: IOKit battery callbacks, sleep/wake and lid state, and
  the temporary idle-sleep assertion used while charging to the target.
- `ChargingLimiterHardware`: minimal AppleSMC transport, capability detection,
  ordered writes, and read-back verification.
- `ChargingLimiterDaemon`: root-owned configuration, the 10-second control loop,
  safe restoration, and authenticated privileged XPC service.
- `ChargingLimiterApp`: SwiftUI `MenuBarExtra`, login/background registration,
  settings, status, and local notifications.

The daemon accepts only the four XPC operations required by the app: get status,
set limit, set enabled, and restore hardware. The bundled local-development
requirement matches the app's signing identifier. Before distributing to anyone
else, strengthen `CHARGING_LIMITER_CLIENT_REQUIREMENT` in the LaunchDaemon plist
with your Apple Developer Team ID and use Developer ID signing plus notarization.

## Tests

Run the unit and UI test targets with full Xcode:

```sh
./Scripts/test.sh
```

The unit suite covers limit boundaries, hysteresis, toggle restoration,
unplug/replug state, sleep/clamshell fallback, notification crossings, SMC key
selection, command ordering, and failed read-back. Hardware is mocked; automated
tests never open AppleSMC or write to a battery controller.

Manual hardware validation must be deliberate and supervised. Confirm normal
adapter and charging state after every failure, sleep/wake cycle, daemon restart,
or helper removal.

## SMC behavior

The independently implemented bridge probes these Apple Silicon key families:

- Charging: `CH0B` + `CH0C`, or Tahoe-era `CHTE`
- Adapter input: `CHIE`, then `CH0J`, then `CH0I`

Every write is immediately read back. Entering discharge inhibits charging before
blocking adapter input. Every restoration path enables adapter input before
enabling charging. Unsupported keys or a verification mismatch fault the
controller and trigger a best-effort safe restoration.
