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
- Compile the app or [download the latest notarized build here](https://github.com/shueber/Touch-Up/releases).
- If you wish, move the app into your Applications folder and add it as a Login item.
- Launch it and allow Accessibility access.
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
Then enable **Touch Up** in both **Privacy & Security → Accessibility** and
**Privacy & Security → Input Monitoring**, quit and relaunch after granting access,
connect the display's USB touch connection, check its **Touchscreens** mapping, and turn on
**Drawing Mode**. Grant permission to the installed copy; permissions may need reapproval
after replacing a development build. The app keeps the upstream bundle identifier.

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

### USB connection crash fix (test build 2)

Five supplied crash reports from macOS 26.6.2 showed a null queue crash in
`IOHIDQueueRegisterValueAvailableCallback`. Failed queue creation now logs a diagnostic,
cleans up device state, and leaves the app running. The app requests Input Monitoring
access at startup; that permission is separate from Accessibility. Queue creation can
also fail for other reasons, so the crash reports alone do not prove permission denial.
After granting access, quit and reopen Touch Up, then reconnect USB. This fix has a
failure-injection regression test; successful Samsung USB input remains a hardware gate.
