# PixCapture iOS (SwiftUI + AVFoundation)

This folder contains the Swift source files and resources for the PixCapture iOS app.

## How to open in Xcode

1. In Xcode, create a new iOS App project:
   - Product Name: PixCapture
   - Interface: SwiftUI
   - Language: Swift
   - Minimum iOS: 18.0
   - Bundle Identifier: app.pixcapture
2. Add all files from `PixCaptureiOS/PixCapture` and `PixCaptureiOS/Resources` into the Xcode project.
3. Ensure these Info.plist keys exist:
   - NSCameraUsageDescription
   - NSPhotoLibraryAddUsageDescription (optional, only if you later export to Photos)

## Notes

- The app stores photos only temporarily (until upload confirmation).
- GPS metadata is stripped before upload.
- Default format is HEIF, with JPEG fallback.
