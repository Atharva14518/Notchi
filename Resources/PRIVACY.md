# Notchi privacy

Shelf cards store local references and security-scoped bookmarks. Removing a card does not delete its original. Vision scanning and OCR run on your Mac. Image, PDF and media actions process files locally.

Sharing sends the selected files to the destination you choose. WhatsApp automation prepares its recipient picker; you choose recipients and confirm Send in WhatsApp. Accessibility permission is used for this automation. Hover and drag monitoring do not need Accessibility access.

Get link uploads a staged copy of the selected file to your configured link service. Folders are zipped. That service stores file metadata and a private object until expiration or revocation cleanup. Anyone holding an active link can download it, subject to its password and download limit. Downloaded copies cannot be recalled. Local setup uses a loopback service; public sharing requires deployment.

Authentication uses the configured Supabase service. Refresh credentials, PKCE secrets and pending upload passwords are stored in the macOS Keychain. Application logs do not include file contents, credentials or full share/upload URLs. Hosting and authentication providers control their own infrastructure diagnostics.

Recent-action suggestions contain action identifiers, not file contents or filenames. Disable them in Settings → Shortcuts. This build includes no analytics or billing integration.
