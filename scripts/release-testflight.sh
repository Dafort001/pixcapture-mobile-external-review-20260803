#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <marketing-version> <build-number> [--upload]" >&2
  echo "Example: $0 2.4 202606111131" >&2
  echo "Add --upload only after the local export has passed manual testing." >&2
  exit 64
fi

MARKETING_VERSION="$1"
BUILD_NUMBER="$2"
UPLOAD_TO_APP_STORE=false
if [[ $# -eq 3 ]]; then
  if [[ "$3" != "--upload" ]]; then
    echo "Invalid option: $3" >&2
    exit 64
  fi
  UPLOAD_TO_APP_STORE=true
fi
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/ios/PIXCAPTURE.xcodeproj/project.pbxproj"
EXPORT_OPTIONS="$ROOT_DIR/tmp-review/AppStoreExportOptions.plist"
ARCHIVE_PATH="$ROOT_DIR/build/Archives/PIXCAPTURE-${MARKETING_VERSION}-${BUILD_NUMBER}.xcarchive"
EXPORT_PATH="$ROOT_DIR/build/Export/PIXCAPTURE-${MARKETING_VERSION}-${BUILD_NUMBER}"
BUNDLE_ID="app.pixcapture.PIXCAPTURE.PIXCAPTURE"

fail_if_weatherkit_in_text() {
  local label="$1"
  local path="$2"

  if rg -a -i 'weatherkit|com\.apple\.developer\.weatherkit' "$path" >/dev/null; then
    echo "Blocked release: WeatherKit reference found in ${label}: ${path}" >&2
    rg -a -n -i 'weatherkit|com\.apple\.developer\.weatherkit' "$path" >&2 || true
    exit 70
  fi
}

fail_if_weatherkit_in_mobileprovision() {
  local profile="$1"

  if [[ ! -f "$profile" ]]; then
    echo "Blocked release: missing embedded provisioning profile: ${profile}" >&2
    exit 70
  fi

  if security cms -D -i "$profile" 2>/dev/null | rg -i 'com\.apple\.developer\.weatherkit|weatherkit' >/dev/null; then
    echo "Blocked release: provisioning profile still contains WeatherKit entitlement: ${profile}" >&2
    security cms -D -i "$profile" 2>/dev/null | rg -n -i 'application-identifier|com\.apple\.developer\.weatherkit|weatherkit|get-task-allow' >&2 || true
    echo "Disable WeatherKit for app.pixcapture.PIXCAPTURE.PIXCAPTURE in Apple Developer, regenerate the profile, delete cached profiles, then archive again." >&2
    exit 70
  fi
}

fail_if_weatherkit_in_cached_profiles() {
  local profile_dirs=(
    "$HOME/Library/MobileDevice/Provisioning Profiles"
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  )
  local profile_dir

  for profile_dir in "${profile_dirs[@]}"; do
    if [[ ! -d "$profile_dir" ]]; then
      continue
    fi

    while IFS= read -r -d '' profile; do
      local decoded
      decoded="$(security cms -D -i "$profile" 2>/dev/null || true)"
      if [[ -z "$decoded" ]]; then
        continue
      fi
      if ! printf '%s' "$decoded" | rg -q "$BUNDLE_ID"; then
        continue
      fi
      if printf '%s' "$decoded" | rg -i 'com\.apple\.developer\.weatherkit|weatherkit' >/dev/null; then
        echo "Blocked release: cached provisioning profile for ${BUNDLE_ID} still contains WeatherKit: ${profile}" >&2
        printf '%s' "$decoded" | rg -n -i 'Name|application-identifier|com\.apple\.developer\.weatherkit|weatherkit|get-task-allow|ExpirationDate' >&2 || true
        echo "Delete this cached profile after disabling WeatherKit in Apple Developer, then archive again." >&2
        exit 70
      fi
    done < <(find "$profile_dir" -maxdepth 1 -name '*.mobileprovision' -print0)
  done
}

verify_no_weatherkit_in_archive() {
  local archive_path="$1"
  local app_path="${archive_path}/Products/Applications/PIXCAPTURE.app"

  fail_if_weatherkit_in_text "archived app bundle" "$app_path"
  fail_if_weatherkit_in_mobileprovision "${app_path}/embedded.mobileprovision"
}

verify_no_weatherkit_in_export() {
  local export_path="$1"
  local ipa

  ipa="$(find "$export_path" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
  if [[ -z "$ipa" ]]; then
    echo "Blocked release: no IPA found in export path: ${export_path}" >&2
    exit 70
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  unzip -q "$ipa" -d "$tmp_dir"
  fail_if_weatherkit_in_text "exported IPA" "$tmp_dir/Payload/PIXCAPTURE.app"
  fail_if_weatherkit_in_mobileprovision "$tmp_dir/Payload/PIXCAPTURE.app/embedded.mobileprovision"
  rm -rf "$tmp_dir"
}

if [[ ! -f "$EXPORT_OPTIONS" ]]; then
  echo "Missing export options: $EXPORT_OPTIONS" >&2
  exit 66
fi

EXPORT_OPTIONS_EFFECTIVE="$EXPORT_OPTIONS"
EXPORT_OPTIONS_TEMP_DIR=""
cleanup_temp_export_options() {
  if [[ -n "$EXPORT_OPTIONS_TEMP_DIR" ]]; then
    rm -rf "$EXPORT_OPTIONS_TEMP_DIR"
  fi
}
trap cleanup_temp_export_options EXIT

if [[ "$UPLOAD_TO_APP_STORE" != true ]]; then
  EXPORT_OPTIONS_TEMP_DIR="$(mktemp -d)"
  EXPORT_OPTIONS_EFFECTIVE="$EXPORT_OPTIONS_TEMP_DIR/AppStoreExportOptionsLocal.plist"
  cp "$EXPORT_OPTIONS" "$EXPORT_OPTIONS_EFFECTIVE"
  /usr/libexec/PlistBuddy -c 'Set :destination export' "$EXPORT_OPTIONS_EFFECTIVE"
fi

if ! [[ "$MARKETING_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "Invalid marketing version: $MARKETING_VERSION" >&2
  exit 64
fi

if ! [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Invalid build number: $BUILD_NUMBER" >&2
  exit 64
fi

fail_if_weatherkit_in_text "app source" "$ROOT_DIR/ios/PIXCAPTURE"
fail_if_weatherkit_in_text "xcode project" "$ROOT_DIR/ios/PIXCAPTURE.xcodeproj"
fail_if_weatherkit_in_cached_profiles

perl -0pi -e "s/MARKETING_VERSION = [0-9]+(?:\\.[0-9]+){0,2};/MARKETING_VERSION = ${MARKETING_VERSION};/g; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER};/g" "$PROJECT_FILE"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

xcodebuild \
  -project "$ROOT_DIR/ios/PIXCAPTURE.xcodeproj" \
  -scheme PIXCAPTURE \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  archive

verify_no_weatherkit_in_archive "$ARCHIVE_PATH"

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_EFFECTIVE" \
  -allowProvisioningUpdates

verify_no_weatherkit_in_export "$EXPORT_PATH"

if [[ "$UPLOAD_TO_APP_STORE" == true ]]; then
  echo "Uploaded PixCapture ${MARKETING_VERSION} (${BUILD_NUMBER}) to App Store Connect."
else
  echo "Exported PixCapture ${MARKETING_VERSION} (${BUILD_NUMBER}) locally to ${EXPORT_PATH}."
fi
