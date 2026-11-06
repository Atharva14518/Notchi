# Permission recovery and the full tour

Hover and automatic drag opening use mouse-only NSEvent monitors, which do not require Accessibility. General now has an independent persisted hover switch. Revoking Accessibility no longer disables hover. This follows Apple's event-monitor requirements: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html

WhatsApp UI automation still requires real Accessibility trust. Onboarding, the Send preflight, and the background AX driver use the same public, non-prompting trust query. The manager checks every second and when the app activates or a window becomes key. Only the user-triggered Open Settings button requests permission. A failed Send opens the recovery guide rather than repeatedly prompting or pretending an old Settings switch proves access.

The guide shows the running bundle's exact path, Show app, Copy app path, Open Settings and Check now. It explains adding the correct copy, replacing obsolete Notchi/Notchi entries, and quitting/reopening when macOS requires it. Local ad-hoc rebuilds can invalidate approvals. Use a consistent signing certificate and bundle identity for reliable update behavior; this change does not override TCC or manufacture trust.

Onboarding is exempt from the panel's minimal-copy rule. Its seven scrollable chapters cover welcome, permission setup/recovery, shelf interactions and persistence, file/media actions, scanning/OCR, sharing/WhatsApp, and settings/login/shortcuts. The footer stays visible, chapter bars navigate, and the permission step celebrates and advances on a newly confirmed grant. Entering an already-approved step leaves its information available to read. Settings → Permission help and the Send tray open that chapter directly; Replay setup opens the complete tour.

## Manual checks

1. Start with Accessibility unconfirmed. Hover over the notch/pill and drag files from Finder: both should open the shelf. Turn Hover off in General: the menu bar and global shortcut should still open it. Restore your preferred setting.
2. From General, click Permission help. Verify the displayed app path matches the running app and Show app reveals it. Copy app path should copy that exact path.
3. Open Accessibility settings, add the exact displayed app, and enable it. Return to the guide: if macOS grants the live process, the state should turn green within one second and advance after the celebration. Do not grant a different Debug/Release copy.
4. If the switch is already enabled but the guide is unconfirmed, follow the old-entry removal/re-add steps. Quit/reopen the same app if macOS requests it. Confirm again. Do not infer success solely from a Settings switch.
5. Revoke Accessibility while running. The WhatsApp status should become unconfirmed within one second, without disabling hover or changing its saved switch. A WhatsApp Send must not run automation without trust.
6. With WhatsApp signed in and trust confirmed, prepare a disposable file. Tap WhatsApp → Send. Verify its native recipient picker opens. Choose recipients and send manually only when intended; QA should cancel the draft without sending.
7. Read all seven chapters; navigate Back/Continue and chapter bars. Long permission instructions should scroll while the footer remains visible. Check the tour on a smaller display and with Increase Contrast/Reduce Motion.
8. In Shelf, verify Command-click multi-select, pin/unpin, drag out, and × removal match the tutorial. Verify removing a card leaves its original file intact.
9. Reopen permission help from Send and from General while the tour is already visible. It should navigate to the permissions chapter, not duplicate the window. Replay setup should start from Welcome.
10. Restart the app. Hover preference, completed onboarding, shortcut and existing shelf persistence choices should remain unchanged.

## Validation

91 unit tests passed, including fresh grant/revocation polling, activation refresh, recovery-guide refresh without prompting, persisted hover settings, legacy schema migration, and WhatsApp's preflight permission gate. Live grant/revocation and WhatsApp recipient selection require the user's macOS approval for the final signed build.

## Files changed in this pass

- `App/AppDelegate.swift` — routes permission-help requests to the tour.
- `App/OnboardingController.swift` — seven chapters, scrollable explanations, direct chapter navigation and grant celebration.
- `App/PermissionControls.swift` — exact-app recovery instructions, app path, Finder/copy actions and fresh checks.
- `App/PermissionManager.swift` — shared public trust query and recovery routing.
- `App/PreferencesView.swift` — independent hover switch and accurate WhatsApp permission status.
- `App/SettingsStore.swift` — persists the hover choice with legacy defaults.
- `Actions/ShareAction.swift` — opens recovery guidance instead of repeatedly prompting on Send.
- `Actions/WhatsAppAutomation.swift` — uses the shared trust query and an accurate unconfirmed-access error.
- `Notch/NotchPanelController.swift` — removes the incorrect AX gate from mouse hover and drag opening.
- `Shelf/SendTrayView.swift` — short Permission help entry point.
- `Tests/SettingsTests.swift` — recovery, hover persistence and revocation regression coverage.
- `Resources/Localizable.xcstrings` — catalogs the expanded onboarding and permission copy.
- `Resources/ManualTests.md` — updates checks for independent hover and the new guide.
- `README.md` — describes current onboarding and permission behavior.
- `PERMISSIONS_AND_ONBOARDING.md` — implementation notes, validation and manual checks.

## Copy before / after

| Before | After |
| --- | --- |
| Hover off (when AX was untrusted) | Hover on/off reflects the user's independent hover switch |
| Enable Accessibility / repeated OS request from Send | Permission help / Accessibility unconfirmed |
| Allow hover and WhatsApp controls. | Explains that only WhatsApp automation needs Accessibility |
| Files, together. | Welcome explains drop, edit and send, followed by six detailed chapters |
| Use manual mode | Continue; hover remains available without AX |
| Drop. Edit. Send. with a demo alone | Demo plus specific shelf, actions, scanning, sharing and settings instructions |

Onboarding intentionally has no word limit in this pass. Panel messages remain short.
