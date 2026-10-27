# Touch-Up
**Universal user-level driver to support touchscreens on macOS**
<hr/>

Most current touchscreens work with Microsoft Windows out-of-the-box as they implement a standardized communication via USB HID. However, nothing happens when connecting these screens to a Mac.
The goal of Touch Up was to provide a simple, general-purpose driver that enables plug-and-play support for touchscreens on macOS. 
The code in this repository provides a user-space driver that reads and processes the HID data into a set of touches and different utilities to inject mouse events into the system.

## What can you do with this App?
The Touch Up **utility app** allows you to control your Mac with any connected touch screen. Touch Up supports clicks, dragging, scrolling, and pinch-to-zoom.
While the behavior of the driver is customizable, the default setting was inspired by iPadOS:

- Tap anywhere on the screen to click objects
- Scroll content by flicking over the screen
- Drag contents by briefly resting your finger before moving it
- Zoom content by pinching two fingers
- Secondary clicks can be performed with two fingers
- You can even enable touching a window to move it to the front like Stage Manager on iPadOS does


### Installing the App
- Build this fork using the instructions below. This fork has not published a notarized release.
- [Upstream releases](https://github.com/shueber/Touch-Up/releases) are separate builds and do not include this fork's Drawing Mode or permission improvements.
- If you wish, move the app into your Applications folder and add it as a Login item.
- Launch it and allow both Accessibility (Device Control & Data Access on macOS 27) and Input Monitoring access.
- Plug in your touchscreen and start touching.


### Drawing Mode (this fork)

In **Touch Up Settings → Gestures**, enable **Drawing Mode** (off by default).
The first finger presses the left mouse button immediately, moves with the button held,
and releases on lift. Taps produce one click; nearby quick taps carry the system double-click
count. A slow stroke or long hold does not seed another double-click sequence.

Extra fingers are ignored until every finger lifts. Drawing Mode disables the legacy
scroll, pinch, secondary-click and window-raising gestures; turning it off restores your
existing settings. Switching modes, turning off **Control Mouse with Touch**, changing
screen mapping, stopping the driver, or losing its device releases the generated button.
Contacts already held during a mode change must lift before input resumes.

For Krijt, select **Draw** to draw or **Pan** to move the canvas. These are ordinary mouse
events: this does not add pen pressure, palm rejection, or pen-versus-finger detection.
**Hold Duration** is not used in Drawing Mode. **Error Resistance** still controls how many
missing HID reports are tolerated before cancellation; explicit liftoff releases immediately.

### Build and share this fork

Requires macOS and Xcode with support for the repository's Icon Composer asset (the local
build was checked with Xcode 27.1). From the repository root:

```sh
xcodebuild -project 'Touch Up.xcodeproj' -scheme 'Touch Up' \
  -configuration Release -derivedDataPath /tmp/touch-up-drawing-build \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
sh Tests/run.sh
```

The universal Intel/Apple Silicon app is at `/tmp/touch-up-drawing-build/Build/Products/Release/Touch Up.app`.
For a local test copy, sign the embedded framework first, then the app with an ad-hoc
signature (this does not use an Apple signing identity or notarize the app):

```sh
codesign --force --sign - '/tmp/touch-up-drawing-build/Build/Products/Release/Touch Up.app/Contents/Frameworks/TouchUpCore.framework'
codesign --force --sign - --entitlements 'Touch Up/Touch_Up.entitlements' '/tmp/touch-up-drawing-build/Build/Products/Release/Touch Up.app'
codesign --verify --deep --strict '/tmp/touch-up-drawing-build/Build/Products/Release/Touch Up.app'
mkdir -p build
ditto '/tmp/touch-up-drawing-build/Build/Products/Release/Touch Up.app' 'build/Touch Up.app'
ditto -c -k --sequesterRsrc --keepParent 'build/Touch Up.app' build/Touch-Up-Drawing-Mode.zip
```

The copied app and ZIP stay in the repository's ignored `build/` folder.
For a colleague's MacBook, send `build/Touch-Up-Drawing-Mode.zip`, extract it, copy **Touch Up.app** to **Applications**,
and quit any other copy of Touch Up before launching. An ad-hoc build is not notarized:
macOS may block a downloaded copy. Use the normal **System Settings → Privacy & Security →
Open Anyway** flow only for the copy you built and trust; workplace policy can prevent this.
Then enable **Touch Up** in both **Privacy & Security → Accessibility**
(**Device Control & Data Access** on macOS 27) and
**Privacy & Security → Input Monitoring**, quit and relaunch after granting access,
connect the display's USB touch connection, check its **Touchscreens** mapping, and turn on
**Drawing Mode**. Grant permission to the installed copy; permissions may need reapproval
after replacing a development build. The fork uses its own bundle identifier, `io.github.Ragura.TouchUp`; permissions and settings from earlier test builds may need to be configured again.

For distribution without that development-build warning, use your own **Developer ID
Application** certificate in Xcode's signing settings, **Product → Archive**, then Organizer's
**Distribute App → Direct Distribution** workflow to sign and notarize. A regular **Apple
Development** certificate is not a Developer ID distribution certificate. This repository
change does not provision a team, change its signing identity, or publish a release.

### Verification and hardware check

`sh Tests/run.sh` compiles a native Objective-C harness and inspects the actual constructed
CGEvents before posting. It checks down/drag/up order, tiny movements, release coordinates,
tap counts and distance in every direction, timeout/hold/stroke exclusion, extra contacts,
mode/output changes, lost reports, origin liftoff, device removal, stop, teardown, and legacy
move/scroll/point-and-click dispatch. It uses a fake monotonic clock and HID stubs: it does
not post to your desktop, open USB devices, or require Accessibility permission.

This is software evidence, not Samsung Flip or MacBook hardware certification. On the target
setup, verify immediate ink from the first contact, continuous slow/fast lines, clean lift,
toolbar taps, double-click, Krijt Pan, extra fingers without jumps, USB unplug during a stroke,
and disabling/re-enabling control while touching. Check that the next contact works and the
button never stays held. Screen rotation, mirroring, sleep/wake, USB report timing, and
workplace security policy still require testing on the actual display and colleague's Mac.

### Compatibility
Touch Up should work with any touchscreen that also works with Windows.
We used the following screens for testing:

- Iiyama TF3222MC and T2336MSC-B2
- 3M C4667PW




## The *TouchUpCore* Framework
Game developers, researchers, and others who need access to all touch data can also benefit from this project by integrating the TouchUpCore **framework** themselves. It provides simple access to all touches recognized on the touch surface, simplifying multitouch prototype development in macOS.

The Touch Up app itself is an example of integrating the TouchUpCore framework. You can have a look at the *DebugView* to see how you can visualize the different touch points. Remember that your app needs an Entitlement to access USB if running in the Sandbox.

### USB connection crash handling

A null HID queue could crash `IOHIDQueueRegisterValueAvailableCallback`.
Failed queue creation now logs a diagnostic,
cleans up device state, and leaves the app running. The app requests Input Monitoring
access at startup; that permission is separate from Accessibility. Queue creation can
also fail for other reasons; queue failure alone does not prove permission denial.
After granting access, quit and reopen Touch Up, then reconnect USB. This fix has a
failure-injection regression test; successful Samsung USB input remains a hardware gate.

### Permission status

Two compact rows at the top of Settings show macOS-confirmed access independently:
**Device Control & Data Access** (called **Accessibility** before macOS 27) and
**Input Monitoring**. **Allow…** requests that permission through macOS. After a
request, **Open Settings** provides explicit navigation if needed; the app does not
open Settings concurrently with the system prompt. Device Control & Data Access uses Core Graphics' event-posting permission
request and preflight check, matching the mouse events this sandboxed app generates.
It does not request broad Accessibility client trust. Requesting never marks access
granted; the user still approves it in macOS.
Statuses refresh when Touch Up becomes active, when Settings opens, and every second
while its Settings window remains open. Closing the window stops polling.

If Input Monitoring becomes granted after being unavailable in this process, Settings
shows a quit/reopen message and a Quit and Reopen button. Whenever either permission still reports unavailable, a shared hint and Quit and Reopen button
explain that users should quit and reopen after enabling permissions in Settings.
This also covers event-posting grants that remain cached as unavailable until restart. Preferences
are saved on quit. No permissions are automatically granted or reset.

The permission tests use injected OS reads/requests and verify grants, revocations,
request refusal, restart guidance, live polling and cleanup. `Tests/PermissionPreview.swift`
renders the real component with fake states at 400 points wide without USB access or
permission prompts. Missing, allowed and restart-required states were visually checked.
The universal build passed; granting permissions and navigating System Settings still
need validation on the installed, signed app on the target Mac.

### Distribution packaging

Run `bash scripts/release.sh prepare` to test and build an unsigned universal app.
The app includes the upstream MIT licence. Local workspaces are ignored by Git.

For an actual release, install a Developer ID Application certificate and store
notarization credentials locally with `xcrun notarytool store-credentials touch-up`.
Enter credentials only into the tool's prompts, never into source files or chat.
Then set `DEVELOPER_ID_IDENTITY` to the full certificate identity and
`NOTARY_PROFILE=touch-up`, and run `bash scripts/release.sh notarize`.
It rebuilds, signs, notarizes and staples the app, creates a drag-to-Applications
DMG, and notarizes and staples that DMG. It stops on failed validation; it does not
publish a GitHub release. Review the saved notarization logs and test the downloaded
DMG and permissions on the target Mac before distributing it to colleagues.

The Quit and Reopen button saves preferences and screen mappings, releases HID input,
then asks macOS to launch a fresh instance of the same app and show its settings.
The old instance exits only after launch succeeds. If launch fails, input resumes and
the settings window displays manual restart guidance. No shell scripts or timed delays
are used for relaunching.
