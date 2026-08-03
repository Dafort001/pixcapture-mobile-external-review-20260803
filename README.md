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
- WebRTC-Timeout, Fehlerweitergabe und sichere Wiederholbarkeit bei Abbruch
- barrierearme Textfarben auf schwarzem Hintergrund
- Release-Prüfliste und Regressionstests

## Verifikation

- Simulatorbuild erfolgreich
- signierter Build für ein verbundenes iPhone erfolgreich
- 66 Unit-/Integrationstests erfolgreich
- Erststart-UI-Test einschließlich Scrollbarkeit und unterer Safe Area
  erfolgreich

Noch offen sind die dokumentierten realen iPhone-Tests für beide
Querformatrichtungen sowie vollständige WebRTC-/Cloud-End-to-End-Läufe unter
unterschiedlichen Netzbedingungen. Der genaue Prüfstand steht in
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
