# PIXCAPTURE iOS external review snapshot

This private repository is an isolated review copy. It is not connected to the production repository and cannot change the production source.

## Provenance

- Released-source commit: `5f2fa402479b688dd173df788a10a60cf0c4b48f`
- Released-source tree: `b7077af20b0c56d42c564e6db4047e32f3cd5bea`
- App version: `3.8`
- App Store build: `202607172137`
- Snapshot date: `2026-08-03`

The `main` branch matches that source commit. The review copy intentionally excludes:

- `ios/PIXCAPTURE/Vendor/opencv2.xcframework`: 327 MB third-party binary/header bundle used only by the hidden Panorama/ArUco implementation; preserved separately with SHA-256.
- `backend/`: legacy/non-iOS backend copy; not referenced by the Xcode project.
- `docs-mobile/`: historical handovers and duplicate export archives, except the candidate branch's single release-verification checklist.
- personal Xcode `xcuserdata`.

The external reviewer should focus on `ios/PIXCAPTURE`, the Xcode project, iOS tests, and the release scripts. Findings should be reported outside this repository until the owner explicitly requests a review branch.

## Fix candidate branch

`candidate/ios-3.9-upload-orientation-safety` is a deliberately small diff from
the released snapshot. Its source provenance is local mobile commit
`3e56988ad081ab006d25edf88e560c49193c6237`, based on the released source above.
It contains only:

- cancellation-safe WebRTC timeout/failure propagation and connection cleanup;
- browser-reported transfer-failure handling;
- restored iPhone Portrait/Landscape Left/Landscape Right configuration;
- viewport-authoritative level mapping without a second landscape-axis rotation,
  plus regression coverage for the observed `-89.8°` error;
- first-run access to capture and local storage without authentication, while
  server transfer continues to require an approved account or valid
  server-issued transfer QR;
- German and English activation guidance for the two SMS stages, approval and
  upload login, without claiming that an activation code is sent by email;
- high-contrast warm-greige text on black instead of orange body/input text,
  with automated contrast coverage;
- the release-verification checklist;
- the ignore rule for the separately archived inactive OpenCV artifact.

This candidate has passed the simulator and signed real-device builds, 66
unit/integration tests, and the targeted fresh-install offline-entry UI test,
including explicit scrolling to the final action and a bottom-safe-area check.
It has not yet passed the required real-iPhone camera/orientation and network
E2E matrix and is not an App Store release.
