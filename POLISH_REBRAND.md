# Notchi polish and rebrand

## Typography follow-up

App-owned text now uses bundled Poppins in Regular, Medium, SemiBold, Bold, ExtraBold and Black weights, including numeric details, toolbar tabs and the AppKit Continuity Camera control. Core Text registers the fonts for this process only; no font installation or runtime download is required. Font files, the complete OFL license and pinned source checksums are under `Resources/Fonts/Poppins/`. SF Symbols and system-owned dialog chrome retain native rendering. Poppins has taller metrics, so action rows are 48pt and content height budgets are 296pt empty / 368pt populated. The roomier spacing is retained.

## Spacing follow-up

The later spacing adjustment supersedes the compact dimensions below: 20pt outer padding, 16pt section gaps, a 64pt drop card, 52pt file chips in a 60pt strip, 12pt between files and actions, and 40pt action rows. Footer buttons have 12pt gaps. Content heights are now 288pt empty, 360pt populated and 392pt for workspaces. Action-row padding leaves room for chip borders and keyboard focus outlines.

Files adjusted: `DesignSystem/PanelLayout.swift`, `Shelf/ShelfView.swift`, `Shelf/FileRow.swift`, `Notch/NotchOverlayView.swift`, and the bundled documentation.

## Panel before / after

Before: a wordmark plus asterisk, a sparse empty area or a 380pt card shelf, uneven footer icons, and mouse-triggered focus outlines.

After:

```text
notchi                           ⚙  pin  ×
┌──────────────────────────────────────┐
│ mascot    Feed me files              │
└──────────────────────────────────────┘
 Compress       Convert       Send
 [recent file] [recent file] … [+N]      ← when populated
┌───────────┐ ┌───────────┐ ┌──────────┐
│ + Files   │ │ ▣ Scan    │ │ ↗ Link   │
└───────────┘ └───────────┘ └──────────┘
                                  ⌃⌥N
```

The populated dashboard is 288pt high instead of 380pt (24% shorter), excluding the camera safe-area inset. The empty dashboard is 244pt so its useful content fits; it replaces the previous sparse 180pt empty state. Outer padding is 16pt, primary gaps 12pt, header controls 28pt with 8pt gaps, and footer buttons 40pt. The four most recent chips retain pop, drag lift, poof, working shake, progress/check and thumbnail behaviors. +N opens every card, including older items. Selected files still expose the full action catalog and multi-file sharing/PDF merge. Success savings still count up. Scanner, Send and Links have a 360pt workspace with scrolling for variable content.

The dashed drop card animates slowly; Reduce Motion stops the dashes. Each open advances through the five short messages. Drag targeting switches to a solid border and “Yes, that one”. The mascot keeps blinks, gaze, gulp, goggles, film reel, reading glasses, happy hop, wave, thumbs up and particles. After 20 seconds without input it lowers its eyelids. Moving, typing, clicking, dropping or starting work wakes it.

## Settings

Five native TabView toolbar tabs: General, Shelf, Actions, Shortcuts, About. The toolbar items contain custom themed controls to avoid AppKit's forced blue tint. The window title follows selection; width is 560pt, with per-tab heights and scrollable Forms. Rows target 44pt including native Form insets. Labels are SF Pro 13pt regular; section labels are muted 11pt medium. Secondary controls are quiet, while selected/on states and the primary action use lime. Display uses a dropdown so long screen names do not truncate inside segments.

Links configuration lives in Shelf. Siri suggestions live in Shortcuts. About includes version/build, the update placeholder, a bundled Privacy document, Replay setup, and collapsible source licenses. Feedback was omitted at the user's request; no destination or sending flow was invented. Reset to defaults resets General preferences and launch at login only; it does not clear the shelf or authentication.

## Branding and data

`AppConfig.appName` is Notchi; its lowercase `wordmark` is the only header branding. No asterisk remains in active app source. Project/scheme/target are Notchi and the bundle ID is `com.notchi.Notchi`.

`Design/notchi-icon.svg` reconstructs the user's supplied reference image (lime rounded tile, dark top notch, oval eyes and mouth). Run `Scripts/make_icons.sh` on macOS to regenerate all ten standard 16–1024px app icon representations and 1x/2x monochrome menu images. The script uses Swift/AppKit, parses the SVG's rect/ellipse primitives, and enlarges small eyes slightly. It fails on unsupported SVG primitives. Xcode compiles AppIcon.appiconset into the application icon. The menu image is explicitly `isTemplate = true`.

Historical names occur only in migration code and its regression fixtures. Existing preferences are copied once; current preferences win. Support files are copied through an atomic staging folder. The old source stays intact so existing bookmarked/imported URLs resolve. Keychain reads attempt a noninteractive legacy lookup and migrate accessible entries; denied old signing access falls back to sign-in. No authentication prompt is bypassed. After the bundle identity change, review Accessibility approval, launch-at-login entries and existing Shortcuts references using the new build. Quit older running copies before opening the renamed build.

## Copy and accessibility

Dashboard messages are at most four words. Empty/loading/error presentations use the mascot and short text; full diagnostic messages remain in accessibility labels/help. Filenames, extracted text, license text and the user's requested detailed onboarding are retained as content. English strings are in the String Catalog, including dynamic dashboard and tab labels.

The keyboard input monitor is process-local and passes events through. Mouse clicks suppress custom focus outlines; Tab enables lime focus outlines. File cards support Tab, Return/Space selection, VoiceOver actions, labeled remove/send buttons and context menus. Reduce Motion uses named fades and disables decorative loops. Increase Contrast raises border and secondary-text contrast. Native file/share/permission dialogs and the window traffic lights retain system-owned chrome.

## Validation and remaining manual checks

- All 113 macOS tests passed, including unchanged engines, geometry/interruption tests and two rebrand migration regressions. Final build/signature results are reported in the delivery message.
- Visually reviewed the real empty panel, the native General/Actions/Shortcuts tabs, the lime toolbar selection and the keyboard-only focus ring. The Display dropdown avoids the previous truncated screen option. Reviewed generated icons at 16, 32, 128 and 1024px.
- Manual: add more than four files; select the overflow card; test Command multi-select, action chips, drag out, removal and result-size animation.
- Manual: hover, drag targeting, 20-second sleepy state, collapse/reopen, pin, workspaces, and disabled-hotkey hint.
- Manual: largest macOS text size, VoiceOver spoken output, Reduce Motion and Increase Contrast. This pass audits their code paths and accessibility trees; it does not claim a completed physical/system-setting sweep.
- Manual: a physical unnotched Mac/external display, independent Spaces, full screen, Stage Manager, hot-plug and lock/wake. Automated geometry cases cover notched, unnotched, negative-coordinate and stacked displays; those tests do not substitute for hardware testing.
- Check for updates remains a labeled placeholder. Feedback is deliberately omitted. Native share extensions, WhatsApp automation and public backend hosting retain their existing platform/provider prerequisites.

## Files changed

The following inventory is generated from before/after hashes of this pass; build products and dependencies are excluded.

<!-- FILE_INVENTORY -->

| File | Change |
| --- | --- |
| `Actions/Compression.swift` | Updated |
| `Actions/MediaActionWorker.swift` | Updated |
| `Actions/NativeActionWorker.swift` | Updated |
| `Actions/ScanCoordinator.swift` | Updated |
| `Actions/ScanRequestExecution.swift` | Updated |
| `Actions/SendAttachmentPreparer.swift` | Updated |
| `Actions/SendFileExporter.swift` | Updated |
| `App/AcknowledgementsView.swift` | Updated |
| `App/AppConfig.swift` | Updated |
| `App/AppDelegate.swift` | Updated |
| `App/BrandMigration.swift` | Added |
| `App/NotchiApp.swift` | Added |
| `App/NotchlyApp.swift` | Removed / renamed |
| `App/OnboardingDemo.swift` | Updated |
| `App/PermissionControls.swift` | Updated |
| `App/PreferencesView.swift` | Updated |
| `App/SettingsStore.swift` | Updated |
| `Backend/README.md` | Updated |
| `Design/notchi-icon.svg` | Added |
| `DesignSystem/Animations.swift` | Updated |
| `DesignSystem/BrandImages.swift` | Added |
| `DesignSystem/Colors.swift` | Updated |
| `DesignSystem/KeyboardFocus.swift` | Added |
| `DesignSystem/NotchiButtonStyle.swift` | Updated |
| `DesignSystem/NotchiControls.swift` | Updated |
| `DesignSystem/NotchiState.swift` | Added |
| `DesignSystem/NotchiWindowChrome.swift` | Updated |
| `DesignSystem/PanelLayout.swift` | Added |
| `DesignSystem/PlayfulEffects.swift` | Updated |
| `DesignSystem/Typography.swift` | Updated |
| `Intents/ShortcutsSettingsView.swift` | Updated |
| `Links/BackgroundLinkUploader.swift` | Updated |
| `Links/LinkKeychain.swift` | Updated |
| `Links/LinkViews.swift` | Updated |
| `Notch/BlobMascot.swift` | Updated |
| `Notch/NotchGeometry.swift` | Updated |
| `Notch/NotchOverlayView.swift` | Updated |
| `Notch/NotchPanelController.swift` | Updated |
| `Notchi.xcodeproj/project.pbxproj` | Added |
| `Notchi.xcodeproj/xcshareddata/xcschemes/Notchi.xcscheme` | Added |
| `Notchly.xcodeproj/project.pbxproj` | Removed / renamed |
| `Notchly.xcodeproj/xcshareddata/xcschemes/Notchly.xcscheme` | Removed / renamed |
| `PERMISSIONS_AND_ONBOARDING.md` | Updated |
| `POLISH_REBRAND.md` | Added |
| `README.md` | Updated |
| `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | Added |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@1x.png` | Added |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png` | Added |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16@1x.png` | Added |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png` | Added |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@1x.png` | Added |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png` | Added |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32@1x.png` | Added |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png` | Added |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@1x.png` | Added |
| `Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` | Added |
| `Resources/Assets.xcassets/Contents.json` | Added |
| `Resources/Info.plist` | Updated |
| `Resources/Localizable.xcstrings` | Updated |
| `Resources/ManualTests.md` | Updated |
| `Resources/MenuBarTemplate.png` | Added |
| `Resources/MenuBarTemplate@2x.png` | Added |
| `Resources/Notchi.md` | Updated |
| `Resources/POLISH_REBRAND.md` | Added |
| `Resources/PRIVACY.md` | Added |
| `Resources/SHORTCUTS.md` | Updated |
| `Scripts/MakeIcons.swift` | Added |
| `Scripts/build_ffmpeg.py` | Updated |
| `Scripts/generate_project.py` | Updated |
| `Scripts/make_icons.sh` | Added |
| `Scripts/sync_strings.py` | Updated |
| `Shelf/FileRow.swift` | Updated |
| `Shelf/ScanWorkspaceView.swift` | Updated |
| `Shelf/SendTrayView.swift` | Updated |
| `Shelf/ShelfItem.swift` | Updated |
| `Shelf/ShelfPersistence.swift` | Updated |
| `Shelf/ShelfView.swift` | Updated |
| `Tests/BrandMigrationTests.swift` | Added |
| `Tests/DropAndPersistenceTests.swift` | Updated |
| `Tests/MediaEngineTests.swift` | Updated |
| `Tests/NotchiTests.swift` | Added |
| `Tests/NotchlyTests.swift` | Removed / renamed |
| `Tests/ScanningTests.swift` | Updated |
| `Tests/SendFlowTests.swift` | Updated |
| `Tests/SettingsTests.swift` | Updated |
| `Tests/SmartActionsTests.swift` | Updated |
| `UI_POLISH.md` | Updated |
