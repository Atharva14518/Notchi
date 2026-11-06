# Notchi: Siri, Shortcuts and Spotlight

The product, project and scheme are **Notchi**, with bundle ID `com.notchi.Notchi`. Say “Notchi” in the phrases below, or substitute the installed app’s displayed name. macOS 14 or later is required.

## Install and discover

1. Build the `Notchi` scheme and run **Notchi.app** once. Use one installed copy, preferably in Applications; quit other Debug/Release copies with the same bundle ID. A stable signing identity also avoids invalidating existing Accessibility approvals on each rebuild.
2. In Notchi Settings, open **Siri & Shortcuts** and click **Open Shortcuts**. The cards shown there are real App Shortcuts published by the app, not downloaded shortcut files.
3. In Shortcuts, look under **App Shortcuts → Notchi**, or create a shortcut and search the action library for **Notchi**, **Compress File**, or another action name. The seven App Shortcuts should appear without a separate import. New registrations may take a moment; quit and reopen Shortcuts after installing a new build if necessary.
4. For an external file, use Shortcuts’ Select File/Get File action and connect its output to **Input file** (or **Files** for Add to Shelf). Expand the action’s optional fields if needed. For a current shelf card, choose **Shelf file** instead. Do not fill both input fields.
5. If both file choices are empty, Compress, Convert and Extract Text use the most recently added available shelf card. Removing a selected card invalidates that selection; it does not silently switch to a different file.

## Test every intent

Use disposable sample files and add **Quick Look**, **Show Result**, **Copy to Clipboard** or **Save File** after the action to inspect its actual output. Conversion/compression results are file values, not path strings.

| Intent | Shortcuts test | Voice test |
| --- | --- | --- |
| Compress File | Select an image → Compress File, Input file = selected file, Preset = Tiny → Quick Look/Save File. Repeat Balanced/Best and a PDF. With no inputs, first add an image to the shelf and use Compress latest. | “Compress my latest file with Notchi.” For a fixed file/preset, save your own shortcut as “Notchi tiny image” and ask Siri to run that name. |
| Convert File | Select an image → Convert File, Format = JPG or PNG → Save File. Then choose a Shelf file from the live list. Try a video/audio file with a matching media format. | “Convert my latest file with Notchi.” The built-in default is PNG; save a named shortcut for a different target, e.g. “Notchi make JPG.” |
| Add to Shelf | Select two files → Add to Shelf, Files = selected files → Open Shelf. Both cards should appear. Repeat with a folder. | Save that workflow as “Notchi add files,” then ask Siri to run it. The direct phrase “Add files to Notchi” may ask you to choose files. Siri cannot invent a file selection. |
| Open Shelf | Run Open Shelf. The panel should expand and pin on the configured display, even after quitting the app first. | “Open my shelf in Notchi.” |
| Extract Text | Select a clear image/scanned PDF → Extract Text → Show Result or Copy to Clipboard. Verify the recognized text. Test an unreadable/non-image file for an error. | “Read my latest file with Notchi” or “Extract text with Notchi.” Use a named shortcut when you need a fixed input. |
| Clear Shelf | Add disposable cards → Clear Shelf → Open Shelf. The cards and persisted references should be gone; originals on disk must remain. It refuses while a live scan/share workspace or file action is active. | “Clear my shelf in Notchi.” This clears all cards; use only a shelf you intend to clear. |
| Open Scanner (extra) | Run Open Scanner. The real scanner source chooser should open. Selecting an iPhone, images or capture area still requires your interaction. | “Scan with Notchi.” This opens the scanner; it does not silently access your camera or capture the screen. |

Compression reuses existing behavior: images become quality-preset JPEGs; PDFs use native PDF compression; video Tiny/Balanced/Best maps to Smallest/Email/High quality; audio uses the existing audio compressor; other files/folders become ZIP archives. A compressed result may be larger for an already efficient source. WebP is offered as a target but reports an error if this Mac cannot encode it. Unsupported source/target combinations fail rather than changing the requested format. Media actions require the bundled LGPL FFmpeg engine.

## Cold-start and visible-panel tests

- For shelf selections after quitting, enable **Shelf → Keep files** first. If it is off, shelf references intentionally do not survive a launch. Passing an explicit Input file works either way.
- Create Select File → Compress File → Save File. Quit Notchi normally and run this shortcut. macOS may start the menu-bar agent in the background; it should process the file without an onboarding window or an expanded notch. Save File belongs to Shortcuts and may display its own chooser.
- Repeat with Convert, Add to Shelf, Extract Text and Clear Shelf. Their intents have `openAppWhenRun = false`. Open Shelf and Open Scanner explicitly open UI and have it set to true.
- Keep the shelf expanded/pinned, run Compress on a selected shelf entity and watch the same icon ring, working mascot, success/checkmark, particles and New result card. Repeat with an incoming Input file: it gets a source card so progress can attach to it.
- Start a media job, cancel immediately, and start another action. The old job must not overwrite the new result. Stopping a shortcut propagates cancellation to the same engine. macOS/Shortcuts impose their own execution limits; very long media jobs may be more suitable in the app.
- Remove or move a card’s source, then run an old saved entity selection. Expect a useful unavailable-file error. The picker should exclude unreadable files and reflect additions/removals while the app runs.

## Spotlight and suggestions

`AppShortcutsProvider` publishes discoverable action metadata, and successful image/PDF compression, image conversion and OCR donate parameter-free action patterns with `AppIntent.donate()`. Donations contain quality/format defaults but no filenames, URLs, file bytes or OCR text. No private file contents are indexed by this integration. **Siri & Shortcuts → Recent actions** controls these app-initiated donations; existing system suggestions/Shortcuts history may remain under macOS control.

Search Spotlight for “Notchi” or a saved shortcut name. Which App Shortcuts, recent suggestions and runnable shortcut results are shown depends on macOS version, Siri/search settings and system ranking. In particular, the expanded runnable Shortcuts experience in Spotlight is a newer macOS feature; this implementation does not use APIs newer than macOS 14 or promise immediate suggestion placement.

## Xcode, entitlements and Info.plist

- No new entitlement, App Group, App Intents extension target, SiriKit `.intentdefinition`, `INIntentsSupported`, `NSUserActivityTypes`, microphone usage key or SiriKit capability is required for these App Intents. They live in the main macOS app target, and App Intents extracts `Metadata.appintents` at build time.
- Keep deployment target macOS 14+, `LSUIElement = true`, the same `CFBundleIdentifier`, and the correct `CFBundleDisplayName`. `AppConfig.appName` remains Notchi. The existing Info.plist already sets these.
- Keep **App Intents metadata extraction** enabled (Xcode’s normal build pipeline); do not strip its generated metadata resource. `AppShortcuts.xcstrings` localizes spoken phrases; `Localizable.xcstrings` holds titles, enum labels, summaries and UI copy. Run `python3 Scripts/generate_project.py` after adding source files, then build and run `python3 Scripts/sync_strings.py` after changing strings.
- Use a consistent Development Team/certificate for releases. The local project remains ad-hoc signed unless you configure a team. This feature does not alter existing Accessibility permissions or code-signing security requirements.
- Siri must be enabled in the user’s macOS settings for voice testing. Shortcuts may ask the user to allow file/folder access. The file intents themselves do not require Accessibility; WhatsApp automation retains its separate approval requirement.
- If enabling App Sandbox later, configure user-selected file read/write access and review security-scoped bookmark persistence and the bundled media process. That is a broader packaging change, not required by this current unsandboxed agent.

## Implementation and validation

- `ShelfItemEntity.swift`: current-shelf entity, stable UUID query, searchable suggestions, compression/format enums.
- `FileIntents.swift`: six requested intents plus the foreground scanner shortcut; file/text return values and Shortcuts progress.
- `IntentRuntime.swift`: shared store/coordinator, latest/explicit selection, cold navigation queue, result integration and shelf guards.
- `IntentFileStager.swift`: background scoped-URL/data imports, safe filenames and owned input lifetime.
- `NotchiShortcuts.swift`: seven ready App Shortcuts and private-content-free action donation.
- `ShortcutsSettingsView.swift`: themed Settings entry, ready-made suggestions and Shortcuts launch.
- `ActionCoordinator.execute`: the shared awaitable execution path for UI and automation; existing engines remain unchanged.

Unit tests directly exercise the real intent `perform()` methods without a panel or AppDelegate. They cover file return types/content, OCR, source preservation, current/removed entities, owned imports, restored bookmark IDs, latest-file fallback, navigation queuing, unsupported formats and clear/workspace guards. Voice and system Spotlight ranking require manual checks on the installed final build.

References: [Apple App Intents](https://developer.apple.com/documentation/appintents), [AppIntent runtime behavior](https://developer.apple.com/documentation/appintents/appintent/openappwhenrun-475kn), [App shortcuts](https://developer.apple.com/documentation/appintents/appshortcut), [donations and discovery](https://developer.apple.com/documentation/appintents/donations-and-discovery), [donate after app interactions](https://developer.apple.com/documentation/appintents/appintent/donate%28%29-1e60c), [Shortcuts and Spotlight on Mac](https://developer.apple.com/videos/play/wwdc2025/260/).

Validation for this pass: **100 tests passed**; the universal Release app contains x86_64 and arm64 slices and passes strict/deep code-signature verification. Its extracted metadata includes all seven intents, seven App Shortcuts, ShelfItemEntity and ShelfItemQuery. Live Shortcuts UI checks were blocked by the computer-use tool’s macOS ScreenCaptureKit failures (-3811/-3812); voice and Spotlight ranking are therefore not claimed as verified. Use the table above for those manual checks.
