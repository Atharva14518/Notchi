# Notchi UI polish

Core UI prose audit: **979 → 298 words (70% reduction)** across ten screen/component source files. This comparison includes tooltip copy and excludes code identifiers and interpolated user data; it is an approximate source-copy count, not a count of every rendered label.

All app-owned controls now use the requested theme. The window and built product are Notchi. The bundle identifier, settings/bookmark keys and Xcode scheme remain compatible with existing installs. macOS-owned permission/file dialogs and native sharing menus retain system chrome. User file names, OCR content, OS service titles and legal notices are content, not shortened instructional copy.

Validation: 89 regression tests passed. Visual review covered the empty panel and Settings; keyboard Tab/Space navigation, lime focus, short info popovers and screen-reader option labels were checked. Reduce Motion paths were audited in code; OS-wide preferences were not changed.

## Every changed file

| File | Change |
| --- | --- |
| [Actions/ActionCoordinator.swift](Actions/ActionCoordinator.swift) | Updated |
| [Actions/ActionOptionsSheet.swift](Actions/ActionOptionsSheet.swift) | Updated |
| [Actions/Compression.swift](Actions/Compression.swift) | Updated |
| [Actions/FFmpegRunner.swift](Actions/FFmpegRunner.swift) | Updated |
| [Actions/FileAction.swift](Actions/FileAction.swift) | Updated |
| [Actions/ImageConversion.swift](Actions/ImageConversion.swift) | Updated |
| [Actions/MediaActionWorker.swift](Actions/MediaActionWorker.swift) | Updated |
| [Actions/MediaPlanning.swift](Actions/MediaPlanning.swift) | Updated |
| [Actions/MediaTrimSheet.swift](Actions/MediaTrimSheet.swift) | Updated |
| [Actions/NativeActionWorker.swift](Actions/NativeActionWorker.swift) | Updated |
| [Actions/PDFActions.swift](Actions/PDFActions.swift) | Updated |
| [Actions/PNGMetadataStripper.swift](Actions/PNGMetadataStripper.swift) | Updated |
| [Actions/ScanCoordinator.swift](Actions/ScanCoordinator.swift) | Updated |
| [Actions/ScanModels.swift](Actions/ScanModels.swift) | Updated |
| [Actions/ScanVisionWorker.swift](Actions/ScanVisionWorker.swift) | Updated |
| [Actions/SendAttachmentPreparer.swift](Actions/SendAttachmentPreparer.swift) | Updated |
| [Actions/SendCatalog.swift](Actions/SendCatalog.swift) | Updated |
| [Actions/SendFileExporter.swift](Actions/SendFileExporter.swift) | Updated |
| [Actions/ShareAction.swift](Actions/ShareAction.swift) | Updated |
| [Actions/WhatsAppAutomation.swift](Actions/WhatsAppAutomation.swift) | Updated |
| [App/AcknowledgementsView.swift](App/AcknowledgementsView.swift) | Updated |
| [App/AppConfig.swift](App/AppConfig.swift) | Added |
| [App/AppDelegate.swift](App/AppDelegate.swift) | Updated |
| [App/GlobalHotkeyManager.swift](App/GlobalHotkeyManager.swift) | Updated |
| [App/LoginItemManager.swift](App/LoginItemManager.swift) | Updated |
| [App/NotchiApp.swift](App/NotchiApp.swift) | Updated |
| [App/OnboardingController.swift](App/OnboardingController.swift) | Updated |
| [App/OnboardingDemo.swift](App/OnboardingDemo.swift) | Updated |
| [App/PermissionControls.swift](App/PermissionControls.swift) | Updated |
| [App/PreferencesView.swift](App/PreferencesView.swift) | Updated |
| [App/SettingsStore.swift](App/SettingsStore.swift) | Updated |
| [DesignSystem/Colors.swift](DesignSystem/Colors.swift) | Updated |
| [DesignSystem/NotchiButtonStyle.swift](DesignSystem/NotchiButtonStyle.swift) | Added |
| [DesignSystem/NotchiControls.swift](DesignSystem/NotchiControls.swift) | Added |
| [DesignSystem/NotchiWindowChrome.swift](DesignSystem/NotchiWindowChrome.swift) | Added |
| [DesignSystem/PillButton.swift](DesignSystem/PillButton.swift) | Updated |
| [DesignSystem/PlayfulEffects.swift](DesignSystem/PlayfulEffects.swift) | Updated |
| [DesignSystem/ProgressRing.swift](DesignSystem/ProgressRing.swift) | Updated |
| [DesignSystem/ScanEffects.swift](DesignSystem/ScanEffects.swift) | Updated |
| [Notch/DropHostingView.swift](Notch/DropHostingView.swift) | Updated |
| [Notch/NotchOverlayView.swift](Notch/NotchOverlayView.swift) | Updated |
| [Notch/NotchPanel.swift](Notch/NotchPanel.swift) | Updated |
| [Notchi.xcodeproj/project.pbxproj](Notchi.xcodeproj/project.pbxproj) | Updated |
| [Notchi.xcodeproj/xcshareddata/xcschemes/Notchi.xcscheme](Notchi.xcodeproj/xcshareddata/xcschemes/Notchi.xcscheme) | Updated |
| [README.md](README.md) | Updated |
| [Resources/Info.plist](Resources/Info.plist) | Updated |
| [Resources/Localizable.xcstrings](Resources/Localizable.xcstrings) | Added |
| [Resources/ManualTests.md](Resources/ManualTests.md) | Updated |
| [Resources/Notchi.md](Resources/Notchi.md) | Added |
| [Resources/Notchi.md](Resources/Notchi.md) | Removed |
| [Resources/THIRD_PARTY_LICENSES.md](Resources/THIRD_PARTY_LICENSES.md) | Updated |
| [Scripts/generate_project.py](Scripts/generate_project.py) | Updated |
| [Scripts/sync_strings.py](Scripts/sync_strings.py) | Added |
| [Shelf/ContinuityCameraButton.swift](Shelf/ContinuityCameraButton.swift) | Updated |
| [Shelf/DropImporter.swift](Shelf/DropImporter.swift) | Updated |
| [Shelf/FileRow.swift](Shelf/FileRow.swift) | Updated |
| [Shelf/ScanWorkspaceView.swift](Shelf/ScanWorkspaceView.swift) | Updated |
| [Shelf/SendTrayView.swift](Shelf/SendTrayView.swift) | Updated |
| [Shelf/ShelfItem.swift](Shelf/ShelfItem.swift) | Updated |
| [Shelf/ShelfStore.swift](Shelf/ShelfStore.swift) | Updated |
| [Shelf/ShelfView.swift](Shelf/ShelfView.swift) | Updated |
| [Shelf/VideoHoverPreview.swift](Shelf/VideoHoverPreview.swift) | Updated |
| [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) | Updated |
| [UI_POLISH.md](UI_POLISH.md) | Added |

## Before → after

| Before | After |
| --- | --- |
| Notchi | Notchi |
| Acknowledgements | Credits |
| Hover sensitivity | Hover |
| Panel size | Panel |
| Show on display | Display |
| Keep shelf across launches | Keep files / Across launches |
| Auto-clear old shelf references | Auto-clear / Old cards |
| Default save location | Save folder |
| Default compression | Compression |
| Default output format | Format |
| After creating a result | Originals |
| Open shelf from anywhere | Open shelf |
| A tiny home for the files in between. | Notchi |
| built with a little help. | — |
| Drop something here | Drop files here |
| Pick images from shelf | Shelf |
| Choose image files… | Files |
| Capture selected area | Capture |
| Searchable text layer | Searchable |
| Create PDF | Save PDF |
| keep the good bit. | Trim |
| let’s do it | Apply |
| your files, in between. | Files, together. |
| open on your terms. | Hover off |
| you’re all set | Hover on |
| drop. remix. send. | Drop. Edit. Send. |
| make yourself at home. | Make it yours. |
| Precise waits longer with a tighter hot zone; Relaxed opens sooner. | Adjust hover timing. (info) |
| Turning this off removes saved shelf references. Files on disk stay in place; current cards remain until you quit. | Remember cards, not copies. (info) |
| Choose any interval from 1 to 3650 days. | —; input still clamps to 1–3650 |
| Expires cards by the date they were added. Originals are never deleted. | Clear cards, keep originals. (info) |
| Used as the starting folder for Send → Save to…. Action results remain temporary until you save them. | Default folder for saved copies. (info) |
| Replace removes the source card from the shelf after successful processing. Your original file on disk is preserved. Failed actions leave the card untouched. | Original files stay untouched. (info) |
| Click Record, then press a modifier and a key. Escape cancels; Delete clears. Unavailable global combinations are rejected. This shortcut works in manual mode without Accessibility. | Escape cancels. Delete clears. (info) |
| Accessibility enables automatic hover/drag mode and WhatsApp’s attachment/contact-picker integration. Without it, open the shelf from the menu bar or global shortcut and use other sharing options. Revoking access stops WhatsApp automation and switches the shelf to manual mode. | Hover on / Hover off; Open Settings |
| Originals stay on your shelf. | — |
| all on your Mac. | — |
| Vision · on your Mac | — |
| Copy & open | Send (WhatsApp handoff) |
| Send with WhatsApp | — |
| Choose a chat → Attach → Document. Use Show files to find your attachments. You can also paste ⌘V or drag a copy where supported. | — |
| Notchi prepares the attachment and opens WhatsApp’s contact picker. Choose your recipients there, then press Send. | — |
| Drag these copies into an app or upload area. Folders are packed as ZIP files. | — |
| You choose the recipient and press Send in \(handoff.app.title). File-type and size limits still apply. | — |
| Show files | Finder icon + tooltip |
| Make a ZIP | ZIP icon + tooltip |
| Copy location | Path icon + tooltip |
| Drop a file at the notch. Make it smaller, change its format, or send it on its way. | — |
| Enable automatic hover and drag mode, or open the shelf from the menu bar and your global shortcut. | — |
| Accessibility enables automatic mode and lets Notchi prepare WhatsApp’s attachment and contact picker. The shelf and other sharing options remain usable without it. | Allow hover and WhatsApp controls. (info) |
| Your shortcut works even when hover is off. Change these any time in Settings. | — |
| The native menu lists nearby devices signed in to your Apple Account. Wi-Fi and Bluetooth must be on. | — |
| Screen capture hides Notchi first. Escape cancels the selection. Processing stays on your Mac. | — |
| Add images to your shelf first, or choose image files from Sources. | No images yet |
| WebP appears only when macOS has a native encoder. Animated images export their first frame. | macOS formats only. (info) |
| Creates an image-only PDF. Text selection, links, forms, annotations, and accessibility structure are flattened. Best for scanned PDFs; size may increase. | Raster PDF; text and forms flatten. (info) |
| Exports JPG; transparency becomes white. Each preset also limits dimensions as shown above. Size savings depend on the original. | JPG; transparency becomes white. (info) |
| 1–20,000 px. Aspect ratio is preserved; smaller images won’t be enlarged. | 1–20,000 px. Preserves proportions. (info) |
| End must be after start and within the clip. | Check the range |
| tap a card for actions · ⌘-click to select files | Select a file for actions. (tooltip) |

## Other removed screen copy

The entries below no longer appear as source copy in those screens. Short replacement controls, icons or states are listed above where applicable.

| Screen | Removed string |
| --- | --- |
| App/PreferencesView.swift | notchi |
| App/PreferencesView.swift | small app.<br>less chaos. |
| App/PreferencesView.swift | Disconnected display (uses main) |
| App/PreferencesView.swift | Automatic hover is enabled |
| App/PreferencesView.swift | Manual mode · hover is off |
| App/PreferencesView.swift | Open Accessibility Settings |
| App/PreferencesView.swift | Auto-clear after days |
| App/PreferencesView.swift | Retention days |
| App/PreferencesView.swift | Choose folder… |
| App/PreferencesView.swift | ⌘⇧N also opens the shelf while Notchi is active. |
| App/PreferencesView.swift | Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")) |
| App/PreferencesView.swift | Check for updates… |
| App/PreferencesView.swift | Automatic updates aren’t connected yet. This is a local build. |
| App/PreferencesView.swift | Project README |
| App/PreferencesView.swift | macOS support ↗ |
| App/PreferencesView.swift | Manual test checklist |
| App/PreferencesView.swift | Replay onboarding… |
| App/PreferencesView.swift | Waiting for approval in Login Items. |
| App/PreferencesView.swift | Press your shortcut… |
| App/PermissionControls.swift | Open System Settings |
| App/PermissionControls.swift | I already enabled it · Check again |
| App/PermissionControls.swift | macOS hasn’t confirmed access for this copy yet. |
| App/PermissionControls.swift | A local rebuild can leave an older Notchi approval enabled. Remove the old Notchi entry in System Settings, then use + to add this exact app and enable it yourself. |
| App/PermissionControls.swift | Show this app in Finder |
| App/PermissionControls.swift | The pane may be named Accessibility or Device Control and Data Access. If macOS asks you to quit and reopen Notchi, do that, then replay onboarding. Manual mode remains available. |
| App/PermissionControls.swift | For development builds, select an Apple Development signing team in Xcode to keep a stable identity across rebuilds. |
| App/PermissionControls.swift | Enabled in Settings, but still waiting? |
| App/OnboardingController.swift | Welcome to Notchi |
| App/OnboardingController.swift | Set up later |
| App/OnboardingController.swift | Drop into the shelf → convert → choose a sharing app. |
| App/OnboardingController.swift | A tiny preview. Your actual files stay untouched. |
| App/AcknowledgementsView.swift | Loading acknowledgements… |
| App/AcknowledgementsView.swift | The bundled engine uses LGPL-only components. H.264 and HEVC use Apple VideoToolbox, with no libx264 or libx265. |
| App/AcknowledgementsView.swift | Source archives & rebuild recipe |
| App/AcknowledgementsView.swift | Full license texts |
| App/AcknowledgementsView.swift | FFmpeg project ↗ |
| App/AcknowledgementsView.swift | License notices are unavailable. Rebuild with the bundled acknowledgements resources. |
| Notch/NotchOverlayView.swift | Notchi. Hover to open. |
| Notch/NotchOverlayView.swift | release to add |
| Notch/NotchOverlayView.swift | files · photos · folders |
| Notch/NotchOverlayView.swift | bringing that in… |
| Notch/NotchOverlayView.swift | Show in Finder ↗ |
| Notch/NotchOverlayView.swift | Scan a document or capture an area |
| Notch/NotchOverlayView.swift | add files |
| Shelf/SendTrayView.swift | \(sharing.session?.items.count ?? 0) selected |
| Shelf/SendTrayView.swift | Ready for \(handoff.app.title) |
| Shelf/SendTrayView.swift | Accessibility access is needed to prepare WhatsApp’s controls. |
| Shelf/SendTrayView.swift | Drag this attachment copy to your chat or upload area |
| Shelf/SendTrayView.swift | In the app’s document picker, press ⌘⇧G and paste this folder location |
| Shelf/ScanWorkspaceView.swift | Paper, meet your shelf. |
| Shelf/ScanWorkspaceView.swift | Scan selected images |
| Shelf/ScanWorkspaceView.swift | Finding your page… |
| Shelf/ScanWorkspaceView.swift | Choose a source to add pages. |
| Shelf/ScanWorkspaceView.swift | Scan look |
| Shelf/ShelfView.swift | \(store.selectedItems.count) selected |
| Shelf/ShelfView.swift | Try that once more. |
| Actions/ActionOptionsSheet.swift | Max dimension (px) |
| Actions/MediaTrimSheet.swift | \(Self.time(end - start)) selected · original stays intact |
| Actions/MediaTrimSheet.swift | Reading duration… |

## Catalog and build

- UI text: `Resources/Localizable.xcstrings` (English source).
- Catalog refresh: build Debug, then run `python3 Scripts/sync_strings.py`.
- Product: `build/Build/Products/Release/Notchi.app`.
- Xcode scheme: `Notchi` (internal compatibility name).
- New design primitives: `NotchiButtonStyle`, `NotchiToggle`, `NotchiPicker`, `NotchiSegmented`, `NotchiInfo`, `NotchiTextFieldStyle`, `NotchiSlider`, `NotchiAttention`, and themed window chrome.
