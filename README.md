# Notchi

## Notchi UI

The app uses ink, lavender surfaces and lime controls throughout Settings, the shelf, Send, scan tools and setup. Settings uses five native toolbar tabs: General, Shelf, Actions, Shortcuts and About. Credits lives in About. Send uses file chips, a single Send action, and Finder/ZIP/path icons. Detailed descriptions live in short info popovers or accessibility help. macOS-owned file, permission and native sharing dialogs retain system chrome.

`AppConfig.appName` supplies the display name and the project generator’s bundle-name setting. The project, scheme and bundle identifier are now Notchi / `com.notchi.Notchi`. `BrandMigration` reads the previous settings and copies support files while preserving old import URLs. Accessibility and login registration may need review after the identity change. The built product is now `Notchi.app`.

All app-owned text uses bundled Poppins weights, registered locally with Core Text. No separate font installation or runtime font download is required. The font license and pinned source checksums are bundled under `Fonts/Poppins`. SF Symbols retain their native symbol rendering.

English UI copy is in `Resources/Localizable.xcstrings`. After a Debug build, run `python3 Scripts/sync_strings.py` to merge compiler-extracted strings and preserve dynamic labels. The custom controls support keyboard activation, lime focus outlines and Reduce Motion. See [the layout, rebrand and file-change audit](POLISH_REBRAND.md).

A native macOS 14+ menu-bar file shelf built with SwiftUI and AppKit. No Swift packages. Media actions bundle an LGPL-only FFmpeg/ffprobe engine. The project uses Swift 5 language mode and requires Xcode 15+ (Swift 5.9+ compiler).

The interface uses a compact black overlay, an acid-green blob mascot, off-white controls, a lowercase wordmark, and compact file chips. File rows use native macOS file icons. The original violet, mint, yellow, and coral palette remains available as design tokens.

Only one app instance presents a shelf. Opening another build reveals the existing shelf and exits the extra process, including direct launches from Xcode. Quit the running copy before launching a freshly rebuilt version. Unit tests use a hostless XCTest bundle, so they do not launch another overlay or access the production shelf.

## Run

1. Open `Notchi.xcodeproj`.
2. Select the **Notchi** scheme and **My Mac** destination.
3. Press **⌘R**. Look for the monochrome face icon in the menu bar; there is no Dock icon.
4. Hover at the top center of the display, or choose **Show Shelf** from the status menu. **⌘⇧N** also opens it while Notchi is active.

On a Mac with a camera notch, the collapsed silhouette matches the notch gap measured from the screen's auxiliary top areas and safe-area inset. On other displays it becomes a 170×30 floating pill, eight points below the top edge. One panel follows the screen containing the cursor, including displays to the left of or above the primary screen. The empty dashboard uses 296 points of content height; a populated shelf uses 368, with 20pt outer padding and 16pt section gaps. Add the camera safe-area inset to the total window height. Scanning, Send and Links use a scrollable 392-point workspace. The dashboard includes the mascot drop card, action teasers, four recent chips with an overflow browser, aligned Files/Scan/Link buttons and the configured hotkey.

The pin keeps the shelf open. With automatic mode enabled, hovering the notch/pill hot zone for the configured dwell time (80 ms by default) expands it; leaving for 400 ms collapses it unless a drag, import, file action, dialog, or share picker is active. Use **add files** as a keyboard-accessible alternative to dragging. Files can be dragged back out of shelf rows, removed individually, cleared, or revealed through their context menus.

## Overlay behavior

- A borderless, transparent, nonactivating `NSPanel` sits above the menu bar without a shadow. Its fixed canvas includes spring overshoot space. Mouse events pass through transparent pixels and rounded corners, using the interpolated silhouette rather than the canvas rectangle for hit testing.
- Global and local `NSEvent` mouse-move/drag monitors drive hover state. A 40 ms common-run-loop watchdog handles stopped pointers, cursor warps, and Finder drag loops that omit callbacks. Local events are returned unchanged; no key events or input permissions are requested.
- `NotchSilhouette` animates width, height, and top/bottom radii together through `animatableData`. Notched screens stay flush at the top; floating pills retain rounded top corners. macOS exposes notch dimensions but not its physical corner radius; the collapsed lower radius uses an eight-point approximation.
- Expansion starts with a 2% anticipation squeeze, then `Animations.bouncy`. Collapse uses `Animations.snappy`. Content starts fading/scaling in 70% of the expansion response later, with 60 ms between groups. One cancellable task owns the choreography; exit, re-entry, display changes, and sleep invalidate stale reveals.
- The blob follows the cursor by at most three points and blinks at randomized 3–5 second intervals. It stops its blink loop while collapsed. Reduce Motion removes the squeeze, spring, gaze tracking, and animated blink.
- `.canJoinAllSpaces`, `.fullScreenAuxiliary`, and `.canJoinAllApplications` support Spaces, full-screen apps, and Stage Manager. `.transient` lets macOS hide the overlay in Mission Control, and `.ignoresCycle` keeps it out of window cycling. Pointer sampling never repeatedly orders the window forward, so it does not fight Mission Control. See [Apple's collection behavior documentation](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct).
- Space transitions briefly disable interaction and reset hover timing. Occlusion disables mouse interception. Screen hot-plug/reconfiguration rebuilds the canvas; sleep, screen sleep, and session locking remove monitors and hide the panel, then restore it on wake. Native dialogs/pickers temporarily retain their screen anchor.

### Terminal

```sh
xcodebuild -project Notchi.xcodeproj -scheme Notchi \
  -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Notchi.app --args --show-shelf
```

`--show-shelf` opens and pins the shelf for previews. Normal launches start collapsed.

## Xcode configuration

- **Nothing needs changing for a local run.** The project includes its shared scheme, Info.plist, macOS 14.0 deployment target, and local ad-hoc signing settings.
- **Signing & Capabilities:** select your team, use your own bundle identifier, and select an appropriate signing identity when preparing a distributable build. The default identifier is `com.notchi.Notchi`. Developer ID distribution also requires an archive and notarization.
- **Info:** `LSUIElement = true` is already set in `Resources/Info.plist`; the delegate also sets accessory activation policy. Do not remove these if you want no Dock icon.
- **App Sandbox:** disabled for this local utility so dropped filesystem paths and the system ZIP tool can be used directly. A sandboxed/App Store variant needs appropriate file-access entitlements, persistent bookmarks if files are restored, and validation of its archiving implementation.
- **Fonts:** SF Pro and SF Rounded come from macOS; no font installation or assets are required.
- **Permissions:** Accessibility is optional and requested only when the user taps Enable. Mouse-only NSEvent monitoring itself does not require AX trust; this build uses trust as an explicit opt-in for automatic hover/drag mode. Without trust, or after revocation, use the menu bar or Carbon global shortcut. The recorder observes only local key-down events while recording; it never installs a global key monitor. The scanner requests Screen Recording access only after you choose Capture selected area. Continuity Camera uses AppKit’s native device menu; no direct camera/microphone capture or event tap is used.
- **App icon:** a custom distribution icon is not included; the status item uses the built-in `tray.and.arrow.down.fill` SF Symbol. Add an AppIcon asset catalog before shipping if desired.

## Drag, drop, and persistence

- When automatic mode is enabled, global/local mouse monitors combine left-button drag events with the drag pasteboard change count to expand on a new system drag. The panel follows the cursor's display. macOS allows custom drag pasteboards, so the native destination also recognizes those when they enter the panel; the standard drag pasteboard cannot advertise every third-party drag globally.
- SwiftUI `onDrop` accepts file URLs, URLs, image data, text, and file data. `DropHostingView` also implements `NSDraggingDestination` and file-promise receiving for apps such as Mail. Both paths use a shared session claim to avoid duplicate imports. Multiple files/folders are accepted together.
- Existing file/folder drops remain references to originals. Text becomes a UTF-8 `.txt` file, web links become `.webloc` files, and raw images or promised attachments are materialized under `~/Library/Application Support/Notchi/Imports` when no persistent source file URL exists. No links are downloaded or opened automatically. Provider callbacks have a 30-second deadline.
- While targeting the panel, a violet glow pulses and the mascot widens its eyes and opens its mouth. Accepted drops trigger a 1 → 1.15 → 0.95 → 1 gulp, sparkles, and staggered card entrance. Cards use Quick Look thumbnails with native file-icon fallback.
- Drag cards out as real file URLs to Finder or another app; originals remain in place. The source card lifts with a scale/shadow. Click **x** to remove with a poof. An upward native trackpad swipe over a hovered card also removes it when macOS delivers that gesture; **x** is available regardless of gesture preferences.
- `ShelfItem` contains `url`, `type: UTType`, `size`, `kind`, and `addedAt`, plus identity and generated-result metadata. The shelf index stores security-scoped bookmarks and card metadata, rather than copies or raw original paths. Access is balanced over each item's lifetime; stale bookmarks are refreshed, and offline entries remain in the index for a later launch.
- The bookmark index is `~/Library/Application Support/Notchi/shelf.json`. Removing/clearing a card removes its saved reference and never deletes its original file. App-owned materialized imports remain in the Imports directory. Action results are temporary files and may eventually be purged by macOS; drag them to Finder to retain a permanent copy.

## Smart actions

Click a card to reveal type-aware chips with staggered springs. Use **⌘-click** to select multiple PDFs; merge uses their shelf order. Chips squash on press. A running source card shakes, its icon gains a progress ring, and the mascot wears goggles and bobs. Indeterminate work shows bouncing dots. Success morphs the ring to a checkmark, pops confetti for 600 ms, hops the mascot, and requests a subtle haptic. Failures show a coral card/message and **retry**. Saved bytes and the rounded percentage count up together, alongside the before/after sizes; outputs that grow are labeled accurately.

- **Images:** convert to PNG, JPG, HEIC, or WebP when ImageIO advertises the encoder. WebP is hidden on Macs without a native encoder. Compression exports JPG with **Tiny**, **Balanced**, or **Best** quality/dimension presets; transparency becomes white. Resize to 25%, 50%, or a custom maximum dimension (1–20,000 px), preserving aspect ratio and avoiding enlargement. Strip metadata creates a PNG without EXIF/GPS blocks, embedded text metadata, or timestamps. A streaming cleanup removes those complete ancillary chunks after ImageIO encoding while preserving the compressed pixels and color profile. Orientation is normalized into the pixels. Animated images export the first frame.
- **PDFs:** compress by rendering pages to JPEG-backed PDF pages at the selected quality/dimensions. The options sheet explains that this produces an image-only PDF: visual annotations are flattened, while selectable text, interactive links/forms, and accessibility structure are lost. Originals are preserved. Compression may increase the size of a small vector PDF. Merge selected PDFs, split every page into a separate PDF card, or extract selectable text to UTF-8. For scanned PDFs, use the separate Read text action to run Vision OCR.
- **Any file/folder:** ZIP through `/usr/bin/ditto`, copy the path, or reveal in Finder. ZIP uses the system ditto executable; image/PDF work uses Apple frameworks. Video/audio work uses the separately bundled LGPL-only FFmpeg engine. A folder ZIP does not invent an original folder byte size for the savings display.
- **Outputs:** each action writes to a unique temporary `Notchi/Results/<UUID>` folder. New cards are inserted beside the source and tagged **New**. Originals are not replaced. Single outputs carry before/after size metadata; split actions show aggregate results. Forward opens the in-panel Send tray; More… opens the full native sharing picker.
- **Architecture:** `Action` defines identity, labels, support checks, and `run(item:progress:) async throws -> ActionResult`. `NativeFileAction` describes operations; `NativeActionWorker` serializes CPU/file work on a background actor. `ActionCoordinator` consumes an `AsyncStream<ActionProgress>` on the main actor and owns options, retry, and presentation. Worker and import code are independent of SwiftUI views.

Settings now includes General, Shelf, Actions, Shortcuts, and About. **⌘⇧N** remains an app-local command; the default global shortcut is **⌃⌥N** through Carbon, with no external shortcut package.

Live verification also covered selecting image action chips, the Tiny/Balanced/Best sheet, a native compression result (675 KB → 34 KB, 95% smaller), the New badge/count-up display, and restoring saved original/result cards after restarting the Release app. This verification used a single Notchi process.

The action audit additionally verified the saved-byte count-up (641 KB saved in that sample), a stationary completion checkmark after indeterminate work, and complete PNG metadata removal without changing IDAT pixel data. Sample verification cards were removed afterward.

## Send

- Each file card has a Forward arrow. The multi-select bar forwards the selected cards, and the footer sends the selection (or all shelf items if nothing is selected).
- The first step is an in-panel tray with large rounded tiles. Tiles spring in with a stagger and wiggle on hover. Native services come directly from `NSSharingService.sharingServices(forItems:)`, with each service's image/title; availability depends on all selected item types and the Mac's share extensions.
- **More…** opens `NSSharingServicePicker`, anchored to its tile. Its native control opens on mouse-down as AppKit specifies. Picking a service does not release the overlay lock: the picker supplies the same `NSSharingServiceDelegate` used for direct tiles, and the panel stays open through `willShareItems`, `didShareItems`, or `didFailToShareItems`.
- **Copy** prepares disposable attachment copies and writes their file URLs to the pasteboard, rather than path strings; folders become ZIP attachments. **Save to…** uses `NSSavePanel`; one item saves as a copy, multiple items save into a new folder with colliding names disambiguated. A background actor stages output before replacement, keeps originals untouched, and rejects saving a folder inside itself.
- Success is confirmed only by `didShareItems`, then selected file previews follow a curved flight toward the chosen tile, the mascot waves, and **Sent!** appears. Copy and save use **Copied!** and **Saved!** respectively. Original shelf entries remain; flight is visual. Cancellations do not report success, and errors return to the tray with a message.
- WhatsApp and Telegram are sharing services only when their installed app registers a share extension on that Mac. When WhatsApp is installed without a native share service, tapping its tile now prepares document copies and uses the explicitly authorized **Accessibility integration** to load them through WhatsApp’s native File picker, open the attachment preview’s audience selector, and clear the preselected chat. WhatsApp’s own searchable recipient list remains open: **you choose contacts and press Send there**. Notchi never presses either WhatsApp Send button or claims delivery. It temporarily hides/releases its overlay and cooperatively activates WhatsApp so the picker is visible. Existing WhatsApp dialogs/drafts, lost focus, missing controls, revoked permission and unconfirmed file selections stop the flow with a useful error. No contact names or message histories are stored. Open any chat once if WhatsApp has no active chat; the actual destinations are chosen afterward in its audience picker. The integration uses observed accessibility identifiers from WhatsApp 26.38.74 and may need updating when WhatsApp changes its UI.
- If Accessibility is unconfirmed, Send opens the detailed Permission help chapter rather than repeatedly prompting. Its Open Settings button explicitly requests access; Check now only refreshes. Menu bar Show Shelf/global shortcut cancels in-flight automation. Native WhatsApp drafts remain under your control. Other fallback apps retain Copy & open. Finder, Copy path and ZIP remain manual recovery options.
- Direct native service tiles also receive prepared copies and re-check `canPerform` before invoking the service. Missing/unreadable files, copy failures and size limits return friendly errors without launching an app. Attachment copies remain in `~/Library/Caches/Notchi/SendAttachments` after the tray closes or Notchi quits, since destination apps may read asynchronously. macOS may eventually purge caches; originals remain intact. More… uses AppKit’s original URL-based native picker.
- The installed WhatsApp build’s Open Document declarations cover media but not generic documents/PDFs. That route caused its “file isn’t supported” alert for a valid PDF, so the fallback uses the native File picker and audience selector instead. WhatsApp’s documented 2 GB per-document ceiling is checked before handoff; other apps/services enforce their own restrictions. A universal guarantee of every file on every platform is not possible. See [WhatsApp’s document attachment guidance](https://faq.whatsapp.com/453914586839706/).
- The share session holds the panel open, freezes its screen anchor, and blocks collapse/quit during service UI, saving, or flight. Back/close is available after the active operation finishes or is cancelled.
- The explicitly requested service-enumeration API is deprecated in macOS 13+ in favor of a standard system menu. It is intentionally retained for this custom tile UI; More… uses the native picker. See [Apple's service query](https://developer.apple.com/documentation/appkit/nssharingservice/sharingservices(foritems:)) and [service completion callback](https://developer.apple.com/documentation/appkit/nssharingservicedelegate/sharingservice(_:didshareitems:)).

Live Send checks verified the tray, native picker opening/cancellation, and Save to… with a byte-for-byte matching copy. Cancelling the picker returns to usable tiles. The More tile exposes a single accessible native button. Real messages were not sent; successful-service behavior is tested with an inert delegate fixture.

On this Mac, the sample PNG query returned **AirDrop, Messages, Notes, Add to Photos, Freeform, Simulator, Journal, and Reminders**. WhatsApp was detected as an installed app and gets the fallback tile. Mail was not returned for that selection; Telegram was not detected under the supported bundle IDs. Results can change with file types, account setup, and extension settings.

## Onboarding and settings

First launch shows a centered, borderless seven-chapter tour: Welcome, Accessibility setup and recovery, Shelf, Actions, Scanning, Sharing, and login/shortcut setup. Onboarding has full explanations and scrollable content; the panel keeps its minimal copy. Replay setup is available from the menu bar and About. The `--onboarding` launch argument replays without clearing preferences. The live SwiftUI demo uses isolated temporary fixtures and never converts or sends user files.

Mouse-only hover and drag opening do not require Accessibility. General has an independent persisted hover switch. WhatsApp automation does require Accessibility; onboarding and the AX driver share the same fresh, non-prompting public query. A one-second common-run-loop timer and activation/window checks detect grants and revocations. Permission help explains how to add the exact running app, repair an obsolete approval, and quit/reopen when macOS requires it. A newly confirmed grant celebrates and advances the tour; revocation leaves hover usable. The menu bar and **⌃⌥N** Carbon shortcut also work without Accessibility. See [permission recovery and manual checks](PERMISSIONS_AND_ONBOARDING.md).

Settings data merges older snapshots with current defaults, preserving completed onboarding, privacy choices and an explicitly cleared shortcut when newer fields are missing. Settings uses one SwiftUI Settings scene, opened by SettingsLink/⌘,. General controls actual launch-at-login status, dwell/hot-zone sensitivity, 400/420/500-point panel width, and cursor/main/named display choice with fallback. Shelf persistence can be disabled without deleting originals; a custom 1–3650-day interval removes references by added date at startup, on settings changes, and on a minute timer. The remembered save folder is a security-scoped bookmark used as the initial Send save directory. Actions preselect format/quality, and can keep both cards or replace the source shelf card after outputs are accepted, while preserving source files on disk. About includes version/build, a clear updates placeholder, bundled README/manual-checklist and macOS support links and replay.

All new screen transitions use named animation presets. Reduce Motion swaps onboarding/settings springs for the short `Animations.fade` preset and makes the tour static. Launch-at-login testing should use a stable Applications copy and appropriate signing for distribution; this local build surfaces service registration errors rather than pretending a stored switch means enabled.

Live checks covered all onboarding screens in manual mode, the Settings scene and pages, shortcut capture/rejection/re-recording, and first-run completion. Accessibility grants, login at reboot, physical global keystrokes and external displays require the [manual checklist](Resources/ManualTests.md). No macOS access was granted and launch at login was left off during these checks.

### Permission enabled in Settings but onboarding still waits

The check always uses macOS's verdict for the running process; an enabled Settings row alone is not treated as permission. Click **Check again** when you return from Settings. If it remains untrusted, expand **Enabled in Settings, but still waiting?** and choose **Show this app in Finder**. Remove the older Notchi entry in System Settings, then use **+** to add and enable that exact app. On newer macOS versions the pane is named **Device Control and Data Access**. Keep using the same app copy; if needed, quit/reopen it and replay onboarding.

Local builds use ad-hoc signing, whose designated requirement contains the build's code hash. Rebuilding can invalidate an older approval even while its Settings toggle remains on. No valid signing identities were available on the development machine during this fix. Configure an Apple Development team/identity in Xcode for a stable development identity; use Developer ID signing for distribution. The app does not reset TCC records or grant itself access. See [Apple's AX trust query](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) and [code-signing identity requirements](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

The reported enabled-toggle/waiting-onboarding mismatch was reproduced on macOS 27.0.1 and persisted after restarting the unchanged build. A stale build approval is a likely cause; that inference cannot identify the stored TCC requirement without accessing private permission data. Regression tests now exercise activation refresh, observer removal, explicit rechecks, and one-second grant/revocation polling. A new final build needs user reapproval if macOS retained an older build's signature.

## Video and audio

Video cards include a silent AVPlayer preview: hover to play, move horizontally to scrub, leave to release the player. Quick Look/native icons remain the fallback for media AVFoundation cannot preview (such as some WebM files). Reduce Motion keeps the thumbnail static.

Tap a video card for one-tap **WhatsApp** (16,000,000-byte target, up to 720p), **Email** (25,000,000-byte target), **Instagram story** (1080×1920 center crop), **Instagram square** (1080×1080 center crop), **Smallest** (480p HEVC) and **High quality** (up to 1080p H.264). Other chips convert MP4/MOV/GIF/WebM, extract MP3/M4A/WAV, trim a start/end range, or mute the video. GIF uses palette generation/palette use; WebM uses libvpx VP9 + Opus. The fit presets preserve aspect ratio and avoid upscaling smaller inputs; Instagram deliberately crops/upscales to its requested canvas.

Audio files are recognized independently and offer MP3/M4A/WAV/FLAC conversion, AAC compression (64 kbps), and range trimming. MP3 uses libmp3lame, M4A uses AAC, WAV uses PCM and FLAC stays lossless. Video/audio output always goes to an owned temporary result folder, with New cards, before/after sizes, count-up savings and Show in Finder. A high-quality conversion or already-small input can grow; those sizes are reported honestly.

For size targets, the video bitrate is `(targetBytes × 0.90 − 65536) × 8 / duration − audioBitrate`. The 10%/64 KB reserve covers muxing and encoder variation, and the finished output must also pass the actual byte-size check. The app never reports an over-limit file as fitting. Impossible budgets or oversized results offer **Try 360p**, then suggest a shorter trim if the lower-resolution budget also cannot fit. Platform limits may vary by account/app version: these are the requested Notchi presets, not a promise that a service accepts every media file.

`FFmpegRunner` is an actor. FFprobe reads duration/stream metadata, with asynchronous AVAsset fallback for missing duration; stderr timestamp progress supplies real percent and an elapsed-time ETA. Pipe readers and process waits run on utility queues. Cancellation invalidates UI callbacks immediately, terminates only that run's Process, escalates to SIGKILL after 250 ms if needed, reaps it and removes partial output. A cancelled run cannot overwrite a newer job. The mascot reels a small filmstrip while work is active. The Cancel pill uses the existing squash press style.

### Engine and signing

`Resources/ffmpeg` and `ffprobe` are universal **arm64 + x86_64**, built from FFmpeg 9.0.2 with `--disable-gpl --disable-nonfree --disable-version3 --disable-autodetect`. H.264/HEVC use VideoToolbox (`-allow_sw 1` permits Apple's software fallback); libx264 and libx265 are absent. LAME 3.100, libvpx 1.15.2 and Opus 1.5.2 are statically linked; `otool -L` shows only Apple system libraries/frameworks. Networking and input/output devices are disabled. Both slices record macOS 14.0 as their minimum OS. Some older Intel Macs cannot encode HEVC through VideoToolbox; the app shows an encoder-unavailable error and offers other formats rather than introducing a GPL fallback.

The final Run Script phase, **Sign LGPL media engines**, validates the configuration and signs each copied nested executable with Xcode's expanded signing identity and hardened runtime before the outer app signature. Local builds use ad-hoc signing; select a team/Developer ID for distribution and perform normal archive/notarization checks. FFmpeg is an executable in Resources, not a linked app library. App signing and codec patent rights are separate concerns.

[Third-party notices](THIRD_PARTY_LICENSES.md), full license texts, source archives with SHA-256 digests, and the rebuild script ship in the app. Settings → **Acknowledgements** displays the notices and opens bundled source/license folders. Run `python3 Scripts/build_ffmpeg.py` to rebuild from the pinned sources (Xcode, Python 3.11+, make and pkg-config required; no Homebrew codec libraries are linked). Then regenerate the Xcode project and build. The bundled helper can also rebuild into a writable `NotchiMediaRebuild` directory outside the app.

Verification: 67 XCTest cases pass, including real four-format audio round trips, real process cancellation/reaping/partial cleanup and starting a subsequent job. Sixteen smoke cases passed on Apple Silicon: all six video presets, four video formats, three audio extractions, trim, mute and the 360p retry. Hardware H.264/HEVC encoding worked here; WhatsApp/Email outputs were checked below their byte ceilings. Intel slices were built and inspected, but **not executed**: this Mac has no Rosetta runtime, and no physical Intel Mac was available. Validate on Intel/macOS 14 hardware before distribution.

## Scanning and OCR

Open the notch and click **Scan** in its footer. Choose **Import from iPhone…** for AppKit’s Continuity Camera menu, pick shelf images, choose image/PDF files, or capture a selected screen area. Continuity requires a compatible nearby device on the same Apple Account with Wi-Fi/Bluetooth enabled; the system decides which devices appear. No phone is required for the other sources. Screen capture requests permission on demand, hides the overlay before selection, and supports Escape to cancel.

Vision detects document edges; Core Image corrects perspective and applies **Color**, **Grayscale**, or **B&W**. A violet sweep, spring outline and animated perspective show the correction. Pages without clear edges remain usable as full images with an explanatory warning; very dark captures ask for better light. Drag page thumbnails to reorder, remove unwanted pages, and enable **Searchable text layer** before creating the PDF. The PDF appears as a **New** shelf card. Closing the scanner retains the draft for this session; quitting discards it. Originals stay untouched, and exported PDFs are temporary until saved or dragged to Finder.

Select an image/PDF card and choose **read text** or **QR / barcode**. Accurate Vision OCR highlights normalized text regions, animates their appearance, and offers **Copy text** for all recognized pages. The mascot wears reading glasses. Recognition requests automatic language detection with English and Hindi when the installed Vision runtime advertises them. Hindi worked on this test Mac; older macOS releases may not include the native Hindi model, in which case a visible notice explains the limitation. OCR can make mistakes; review copied text and searchable PDFs. Barcode payloads are shown explicitly; only HTTP(S) links without embedded credentials offer **Open link**, and nothing opens automatically.

All scanning uses Apple frameworks (Vision, Core Image, ImageIO, Core Text, PDFKit and AppKit), independently of the media engine. A background actor coordinates decoding and PDF work; blocking Vision requests run on a dedicated queue. Export forwards per-page OCR progress and a percentage to the panel. Each native request has a 45-second deadline; timeout releases the UI with a friendly message, preserves the draft and allows a retry with Searchable text layer disabled. Cancellation returns promptly even if a native request is slow to stop, and stale results are rejected. Drafts are capped at **20 pages**, normalized to a **2200 px** long edge with smaller UI previews. Searchable PDFs retain page images and add an invisible, position-matched Core Text layer. Output is a new scan PDF; existing PDF forms, interactive content and signatures are not preserved in that raster scan.

Automated fixtures are generated with Core Graphics/Core Text: English/Hindi pages, a perspective-warped document, low-light input, a rotated image-only PDF and a QR code. Tests cover OCR, document correction, all looks, invisible PDF text, page ordering, coordinate mapping and safe barcode links. Native phone capture and Screen Recording permission prompts require the [manual checklist](Resources/ManualTests.md); tests never invoke devices, request permissions, send files or open URLs.

## File guide

| File | Purpose |
| --- | --- |
| `App/NotchiApp.swift` | SwiftUI entry point, one MenuBarExtra/status menu with SettingsLink, delegate connection, and Settings scene. |
| `App/AppDelegate.swift` | Single-instance lifecycle, overlay setup, permission polling, global hotkey, onboarding, and safe Quit. |
| `App/PreferencesView.swift` | General/Shelf/Actions/Shortcuts/About settings, login control and shortcut recorder. |
| `App/SettingsStore.swift` | Persisted settings snapshot, defaults, shortcut model, and security-scoped save-folder access. |
| `App/PermissionManager.swift` | Optional AX prompt, non-prompting live checks, activation/key-window refresh, polling, and exact-app recovery. |
| `App/PermissionControls.swift` | Shared Check again, Settings, exact running app location, and stale-approval help. |
| `App/LoginItemManager.swift` | Real SMAppService registration/status/error and approval handling. |
| `App/GlobalHotkeyManager.swift` | Carbon global registration, collision recovery, and scoped local shortcut capture. |
| `App/OnboardingController.swift` | Centered borderless first-run window and cancellable four-step flow. |
| `App/OnboardingDemo.swift` | Looping live file-card/chip/progress/send components with isolated in-memory data. |
| `Resources/ManualTests.md` | Full onboarding, permissions, login, shortcut, settings, and regression manual checklist. |
| `Tests/SettingsTests.swift` | Isolated persistence, retention, replacement, permission changes, geometry, shortcut and bookmark checks. |
| `Notch/NotchPanel.swift` | Transparent, borderless, nonactivating floating `NSPanel`, visible across Spaces. |
| `Notch/NotchPanelController.swift` | Cursor display selection, interpolated pass-through hit testing, lifecycle handling, and hover/sharing coordination. |
| `Notch/NotchGeometry.swift` | Calculates collapsed/expanded sizes and top-centered positions using screen safe areas. |
| `Notch/HoverDetector.swift` | Global/local mouse monitors, drag watchdog, and deterministic hover debounce/exit timing. |
| `Notch/SystemDragTracker.swift` | Testable system-drag detection from movement, button state, and pasteboard changes. |
| `Notch/DropHostingView.swift` | Native dragging destination underneath the SwiftUI drop surface. |
| `Notch/NotchSilhouette.swift` | Custom shape with animatable size and corner radii, plus presentation hit-test geometry. |
| `Notch/OverlayPresentation.swift` | Cancellable anticipation, expansion, stagger, and collapse state machine. |
| `Notch/NotchOverlayView.swift` | Hosts the silhouette, staged mascot/empty state, compact file content, and overlay controls. |
| `Notch/BlobMascot.swift` | SwiftUI blob shape, eyes, randomized blinking, and limited cursor following. |
| `Shelf/ShelfItem.swift` | File identity, URL, UTType/kind, dates, sizes, and result size comparisons. |
| `Shelf/DroppedFile.swift` | Compatibility alias for the original file model name. |
| `Shelf/ShelfStore.swift` | Selection, drop claims, import state, bookmark restoration, scoped access, and shelf mutations. |
| `Shelf/ShelfPersistence.swift` | Bookmark records, atomic JSON storage, injectable in-memory storage, and import locations. |
| `Shelf/DropImporter.swift` | Native pasteboard decoding, async providers/promises, materialization, safe names, and callback deadlines. |
| `Shelf/ThumbnailCache.swift` | Quick Look thumbnail generation with bounded caching and native-icon fallback. |
| `Shelf/ShelfView.swift` | Horizontal cards, selected-file action chips, progress, savings, and inline retry. |
| `Shelf/FileRow.swift` | `FileCard`: thumbnail, selection, lift/drag, progress/checkmark, new tag, poof, and context menu. |
| `Actions/FFmpegRunner.swift` | Background Process/pipe runner, duration probing, timestamp progress, ETA and bounded cancellation. |
| `Actions/MediaPlanning.swift` | Media operations, bitrate budgets, stream/progress models and codec/filter command plans. |
| `Actions/MediaActionWorker.swift` | Media result staging, output-size enforcement and error/cancellation cleanup. |
| `Actions/MediaTrimSheet.swift` | Simple validated start/end sliders and seconds fields. |
| `Shelf/VideoHoverPreview.swift` | Muted native playback/scrubbing with static thumbnail fallback and lifecycle cleanup. |
| `DesignSystem/MediaEffects.swift` | Pausable filmstrip/reel drawing for the working mascot. |
| `App/AcknowledgementsView.swift` | In-app third-party notices and bundled source/license access. |
| `Scripts/build_ffmpeg.py` | Pinned-source, LGPL-only universal engine build and source/license packaging. |
| `Scripts/sign_media_engines.sh` | Validates licensing flags and signs nested engines with hardened runtime. |
| `THIRD_PARTY_LICENSES.md` | Versioned FFmpeg, LAME, libvpx and Opus attribution/distribution notes. |
| `Tests/MediaActionsTests.swift` | Bitrate, chunked progress parsing, codec planning, trim and missing-audio checks. |
| `Tests/MediaEngineTests.swift` | Real audio conversions, cancellation/partial cleanup and stale-job callback protection. |
| `Actions/ScanModels.swift` | Scan pages, OCR/barcode results, friendly errors and coordinate/reordering helpers. |
| `Actions/ScanVisionWorker.swift` | Background Vision segmentation/OCR/barcodes, image correction and searchable multi-page PDF export. |
| `Actions/ScanRequestExecution.swift` | Dedicated Vision queue, bounded request deadline and immediate cancellation without blocking the UI. |
| `Actions/ScanCoordinator.swift` | Scan draft lifecycle, cancellation, source selection, progress and hidden-panel area capture. |
| `Shelf/ScanWorkspaceView.swift` | Sources, shelf picker, reorderable page editor, scan looks and OCR/code results. |
| `Shelf/ContinuityCameraButton.swift` | Native contextual device menu and NSServicesMenuRequestor image/PDF receiver. |
| `DesignSystem/ScanEffects.swift` | Scan-line, animatable document outline and perspective flattening. |
| `Tests/ScanningTests.swift` | Generated sample-image OCR, correction, PDF text, QR, rotation and geometry checks. |
| `Actions/ActionCoordinator.swift` | Options, async stream consumption, job state, generated cards, haptics, and retry. |
| `Actions/FileAction.swift` | Action protocol, operation catalog, progress messages, and results. |
| `Actions/NativeActionWorker.swift` | Serial background execution, temporary output ownership, and failure cleanup. |
| `Actions/PDFActions.swift` | PDFKit merge/split/text extraction and raster compression with JPEG pages. |
| `Actions/ActionOptionsSheet.swift` | Native format, quality, and custom resize options. |
| `Actions/ImageConversion.swift` | Native format detection, conversion, compression, resize, orientation normalization, and metadata export. |
| `Actions/PNGMetadataStripper.swift` | Bounded streaming removal of PNG metadata chunks with atomic output replacement. |
| `Actions/Compression.swift` | Temporary file staging and ZIP creation without shell interpolation. |
| `Actions/ShareAction.swift` | Send session, service/picker delegates, copy/save/app handoffs, panel locking, flight, and toast state. |
| `Actions/SendCatalog.swift` | Native service discovery and installed WhatsApp/Telegram fallbacks. |
| `Actions/SendLifecycle.swift` | Testable share phases, snapshots, toast/flight models, and curved flight geometry. |
| `Actions/WhatsAppAutomation.swift` | Bounded background AX bridge for verified file selection and WhatsApp’s native recipient picker; never presses Send. |
| `Tests/WhatsAppAutomationTests.swift` | Recipient-flow sequencing, failure, late cancellation, permission gating and repeat launch checks with inert drivers. |
| `Actions/SendAttachmentPreparer.swift` | Background attachment copies, duplicate-name handling, folder ZIPs, optional archives and size checks. |
| `Actions/SendFileExporter.swift` | Background staged file/folder copying and safe destination checks. |
| `Shelf/SendTrayView.swift` | App tile grid, selected previews, native More control, and animated file flights. |
| `DesignSystem/Colors.swift` | Acid green, paper, ink, the original accent palette, and dark surface/text tokens. |
| `DesignSystem/Typography.swift` | SF Rounded display/heading/button, SF Pro body/caption, and monospace detail presets. |
| `DesignSystem/Animations.swift` | Named `Animations` presets and all choreography, hover, and blink timing constants. |
| `DesignSystem/PillButton.swift` | Capsule button with a 0.92 press scale, squash press, and bouncy release. |
| `DesignSystem/IconBadge.swift` | Reusable solid-color SF Symbol badge. |
| `DesignSystem/PlayfulEffects.swift` | Sparkles/poof, bouncing dots, animated savings, card shake, and native swipe monitoring. |
| `DesignSystem/ProgressRing.swift` | Animatable sampled path that morphs a progress arc into a checkmark; supports Reduce Motion. |
| `Resources/Info.plist` | Bundle metadata, minimum OS, and menu-bar-agent flag. |
| `Tests/SendFlowTests.swift` | Picker/service locking, confirmed success/cancellation, private-pasteboard copy, safe export, and flight path checks. |
| `Tests/SmartActionsTests.swift` | Real image conversion/compression/resize/metadata tests and PDF action round trips. |
| `Tests/DropAndPersistenceTests.swift` | Drag detection, multiple native URLs, provider deduplication, text/link imports, and bookmark restore/offline behavior. |
| `Tests/NotchiTests.swift` | Geometry, hit testing, debounce, animation cancellation/reversal, Reduce Motion, shelf retention, ZIP handling, and real image encoding. |
| `Scripts/generate_project.py` | Regenerates the Xcode project and shared scheme from the source folders; run after adding files. |
| `Notchi.xcodeproj/project.pbxproj` | App/test targets, folder groups, source membership, and build settings. |
| `Notchi.xcodeproj/xcshareddata/xcschemes/Notchi.xcscheme` | Shared Run, Test, Profile, Analyze, and Archive actions. |
| `.gitignore` | Excludes build products and user-specific Xcode state. |

Animation curves and animation-related durations are centralized in `Animations.swift`. System Reduce Motion disables custom spatial animations. System dialogs and native controls use macOS-managed behavior.

## Verify

Verified locally with Xcode 26.1.1 / Swift 6.2.1 in Swift 5 language mode. All 89 tests pass, including real PNG/JPG encoding, ordered compression presets, orientation and EXIF/GPS stripping, PDF actions, bookmark round trips, multi-file pasteboard imports, provider session deduplication, and overlay interruption. The hostless test target compiles the shared production sources directly, excluding the app entry point/delegate. Tests use temporary directories and in-memory persistence; they neither launch an overlay nor clear the user's saved shelf. Native conversion tests cover every advertised encoder on the test Mac. Additional regressions verify complete EXIF/GPS removal, unchanged PNG IDAT bytes, truncated-input safety, rotated PDF dimensions, action filtering, and savings rounding.
Run **⌘U**, or:

```sh
xcodebuild -project Notchi.xcodeproj -scheme Notchi \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' test
```

Manually check hover/collapse, a Finder drop, pin/unpin, image conversion, ZIP export, sharing-picker cancellation, Preferences, and Quit. Before distribution, also check a physical notched Mac, an unnotched external display with independent Spaces, full-screen apps, Mission Control, Stage Manager, display hot-plug, and lock/wake. Automated tests cover their geometry and interruption logic; they cannot emulate every WindowServer/display configuration.

Apple references: [Quick Look thumbnails](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator), [ImageIO encoders](https://developer.apple.com/documentation/imageio/cgimagedestinationcopytypeidentifiers()), [native drag destinations](https://developer.apple.com/documentation/appkit/nsdraggingdestination), [NSScreen auxiliary top area](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc), [NSPanel](https://developer.apple.com/documentation/appkit/nspanel), and [NSItemProvider](https://developer.apple.com/documentation/foundation/nsitemprovider).

## Siri and Shortcuts

The six file/shelf App Intents and a scanner shortcut reuse the same engines and awaitable action coordinator. Background file actions do not need a panel; the live shelf uses its existing animations. Open **Settings → Siri & Shortcuts** for the ready-made App Shortcuts. See the [per-intent Shortcuts/voice tests and Xcode notes](Resources/SHORTCUTS.md). No new entitlement or Info.plist key is required for this main-app App Intents integration.

## Get a link

File cards now offer **Get link** with 1-hour/24-hour/7-day expiry, optional passwords and download limits. Background URLSession uploads report real byte progress, publish an immutable private R2 object, then copy the link. **My links** supports countdowns, Copy and Revoke. Sign-in uses Supabase Apple web OAuth/email magic links and macOS Keychain refresh credentials.

The [backend README](Backend/README.md) contains local Supabase/R2-emulation setup, environment variables, the Postgres migration, deployment instructions and tests. The [Mac link guide](Resources/LINKS.md) covers Xcode and manual tests. The local Supabase and Worker setup is running. Native email sign-in, a real background upload, automatic link copy and a browser download were verified with matching file bytes. Backend integration tests also verified passwords, download limits, immutable output, ticket replay rejection and revocation. No cloud deployment or billing integration was created. Real Apple authorization and production R2 need provider credentials and live validation.
