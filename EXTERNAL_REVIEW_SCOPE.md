# PIXCAPTURE iOS 3.9 – externer Prüfstand

Dieses Repository enthält den vollständigen, eigenständig prüfbaren Swift-Code
der iOS-App in `ios/`. Außerhalb des Repos liegende interne Handovers sind keine
Voraussetzung für die technische Prüfung.

Die Kopie basiert auf dem privaten Mobile-Commit
`685af1b1677e01147d35d68a51cf391b52c5793e`. Das öffentliche Repository ist
technisch isoliert; Änderungen daran verändern das private Produktions-Repo
nicht.

## Verbindlicher Funktionsstand

- Fotografieren ist vor Anmeldung möglich; eine freigeschaltete Anmeldung oder
  ein gültiger Web-Connect-QR ist erst vor der Serverübertragung erforderlich.
- Die Nivellierung arbeitet viewportbezogen in Portrait, Landscape Left und
  Landscape Right.
- Ein Upload gilt erst nach bestätigter Paket-ID, Bytezahl und SHA-256 als
  erfolgreich; Fehler und Abbrüche lassen lokale Dateien wiederholbar zurück.
- Foto-/Video-/Panorama-Medien und Grundriss sind getrennte Datenprodukte. Ein
  Medienupload enthält keine Grundrissdateien oder `linked_floorplan`-Metadaten.
- Der freigebbare Grundriss enthält ausschließlich den bemaßten Plan als PNG
  und visuelles PDF, keine Wohnfläche/WoFlV, Adresse, Jobkennung, CSV/CRM oder
  OpenImmo-Daten.
- DNG-Aufnahmen bevorzugen Sensor-Bayer; der konkrete RAW-Typ wird zusammen
  mit App-/Build- und Koordinatensystem-Provenienz protokolliert.

## Besonders zu prüfende Dateien

- `ios/PIXCAPTURE/Camera/CameraManager.swift`
- `ios/PIXCAPTURE/Views/LevelOverlayView.swift`
- `ios/PIXCAPTURE/Services/PixcaptureUploadService.swift`
- `ios/PIXCAPTURE/Services/CompanionTransferService.swift`
- `ios/PIXCAPTURE/Views/FloorplanWorkflowView.swift`
- `ios/PIXCAPTURE/Views/FloorplanMeasureView.swift`
- `ios/PIXCAPTURE/Models/FloorplanProject.swift`
- `ios/PIXCAPTURE/Services/FloorplanComposerRenderer.swift`
- `ios/PIXCAPTURETests/`

## Nachweis und Grenzen

Der aktuelle Simulatorlauf umfasst 82 bestandene Unit-/Integrations-/
Logiktests. Build und Tests ersetzen nicht die in
`docs-mobile/RELEASE_3_9_VERIFICATION_20260803.md` aufgeführten realen
iPhone-, AR-, Netz- und End-to-End-Prüfungen. Bis diese protokolliert sind, ist
3.9 nicht zur Apple-Einreichung freigegeben.
