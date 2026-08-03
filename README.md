# PIXCAPTURE iOS — aktueller Quellstand

Dieses öffentliche Repository enthält auf `main` den vollständigen aktuellen
Stand der nativen PIXCAPTURE-iPhone-App vom 3. August 2026. Es ist eine
isolierte Prüfkopie und technisch nicht mit dem privaten Produktions-Repository
verbunden.

## Enthaltener Stand

- Kamera, lokale Aufnahmesicherheit, Galerie und Grundrissfunktionen
- lokales Fotografieren ohne Anmeldung; Freischaltung erst vor Servertransfer
- Aktivierung mit zwei SMS-Stufen und anschließendem Upload-Login
- korrigierte Portrait-/Landscape-Unterstützung und Nivellierungsachsen
- WebRTC-Timeout, Browser-ACK mit Paket-ID/Bytezahl/SHA-256,
  Fehlerweitergabe und sichere Wiederholbarkeit bei Abbruch
- gehärteter lokaler Companion-Receiver mit Pflicht-Pairing und exakter
  Receipt-Prüfung
- Keychain-Migration ohne Delete-vor-Add, Vordergrund-Uploadvertrag,
  Kameraberechtigungs-Recovery und lokalisierte Berechtigungstexte
- barrierearme Textfarben auf schwarzem Hintergrund
- Release-Prüfliste und Regressionstests

## Verifikation

- sauberer arm64-Releasebuild: Version 3.9, Build 202608031930
- 74 Unit-/Integrations-/Logiktests erfolgreich
- 15 UI-/Launch-Tests: 12 erfolgreich, drei echte Netz-/Auth-E2E-Tests ohne
  produktive Zugangsdaten beziehungsweise QR-Payload übersprungen
- Erststart-UI-Test einschließlich Scrollbarkeit und unterer Safe Area sowie
  Galerie-Uploaddialog mit wiederhergestelltem realem Testbestand erfolgreich
- reales 1.849.171.856-Byte-Paket vom Companion mit Bytezahl und SHA-256
  bestätigt; absichtlich falscher Hash mit HTTP 422 abgewiesen

Noch offen sind die dokumentierten realen iPhone-Tests für beide
Querformatrichtungen, die Provisionierung und Prüfung eines produktiven
TURN-Relays sowie vollständige WebRTC-/Cloud-End-to-End-Läufe. Sechs
Strict-Concurrency-Warnungen im historischen `CameraManager` bleiben sichtbar
und sind ebenfalls ausdrücklicher Prüfgegenstand. Der genaue Prüfstand steht in
[`docs-mobile/RELEASE_3_9_VERIFICATION_20260803.md`](docs-mobile/RELEASE_3_9_VERIFICATION_20260803.md).
Der dazugehörige eigenständige Produkt- und Sicherheitsvertrag steht in
[`docs-mobile/EXTERNAL_REVIEW_CONTRACT.md`](docs-mobile/EXTERNAL_REVIEW_CONTRACT.md).

## Prüfbereich

Für eine externe Codeprüfung sind insbesondere relevant:

- `ios/PIXCAPTURE`
- `ios/PIXCAPTURE.xcodeproj`
- `ios/PIXCAPTURETests`
- `ios/PIXCAPTUREUITests`
- `scripts`

Das inaktive, rund 327 MB große OpenCV-Drittanbieterpaket, historische
Dokumentarchive, persönliche Xcode-Daten und eine nicht verwendete alte
Backendkopie sind bewusst nicht Bestandteil dieses Prüf-Repositories.
