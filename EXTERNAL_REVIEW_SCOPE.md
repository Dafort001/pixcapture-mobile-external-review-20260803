# PIXCAPTURE iOS 3.9 – externer Prüfstand

Dieses Repository enthält den vollständigen, eigenständig prüfbaren Swift-Code
der iOS-App in `ios/`. Außerhalb des Repos liegende interne Handovers sind keine
Voraussetzung für die technische Prüfung.

Die Kopie basiert auf dem privaten Mobile-Commit
`2a276e091688b96d817aea6e6d4734051212ca94`. Das öffentliche Repository ist
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

Der aktuelle Simulatorlauf umfasst 86 bestandene Unit-/Integrations-/
Logiktests. Die beiden physischen Querformatlagen, die zentrierte grüne
Nivellieranzeige und zwei reale DNG-/EXIF-Orientierungen wurden auf einem
iPhone 15 Pro Max geprüft. Diese Nachweise ersetzen nicht die übrigen in
`docs-mobile/RELEASE_3_9_VERIFICATION_20260803.md` aufgeführten Portrait-,
Galerie-/Export-, AR-, Netz- und End-to-End-Prüfungen. Auch die sichtbaren
Grundriss-Erklärtexte müssen noch an den geänderten Funktionsumfang angepasst
werden. Bis dahin ist 3.9 nicht zur Apple-Einreichung freigegeben.
