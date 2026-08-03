# PIXCAPTURE iOS — externer Prüfstand

`main` ist der vollständige aktuelle Prüfstand vom 3. August 2026. Es gibt
keinen getrennten Zukunfts- oder Kandidatenstand mehr.

## Herkunft und Isolation

- Aktueller lokaler Swift-Stand:
  `010761ae8d03e0229e08fc0d469b3a14d1d70988`
- Öffentlicher Prüfstand nach Übernahme auf `main`: siehe aktuelle HEAD-ID
- Ursprünglicher App-Store-Ausgangsstand bleibt ausschließlich über den
  unveränderlichen Git-Tag `source-5f2fa402-ios-3.8` nachvollziehbar.
- Dieses Repository besitzt keinen Remote oder automatischen Weg zum privaten
  Produktions-Repository.

## Inhalt der aktuellen Änderungen

- exakter WebRTC-Abschlussvertrag: Paket-ID, Bytezahl und SHA-256 müssen vom
  Browser bestätigt werden; Fehler, Kanalabbruch und Timeout bleiben pending
- gemeinsamer ICE-Konfigurationsvertrag mit optionalen kurzlebigen coturn-
  Zugangsdaten; produktiver TURN-Dienst ist noch nicht provisioniert
- lokaler Companion verlangt Pairing und akzeptiert nur ein exakt passendes
  Erfolgs-Receipt ohne Warnungen
- iPhone-Unterstützung für Portrait, Landscape Left und Landscape Right
- einheitlicher Orientierungsresolver mit physischer Geräteorientierung als
  Priorität und ohne zweite Landschaftsachsen-Drehung
- Regressionstests für den beobachteten Fehlerwert `-89,8°`
- Fotografieren und lokale Speicherung ohne Anmeldung
- Freischaltung erst vor Servertransfer über zwei SMS-Stufen
- Upload-Login mit E-Mail-Adresse und selbst gewähltem Web-Passwort
- hellblauer numerischer Leveltext statt rot/grüner Information allein
- lokalisierte Hauptfehlerpfade und InfoPlist-Berechtigungstexte
- sichere Keychain-Aktualisierung/Migration, atomarer Video-Stop und expliziter
  Vordergrund-Uploadvertrag
- expliziter UI-Test für Scrollbarkeit und untere Safe Area

## Nachweisstand

Der saubere arm64-Releasebuild 3.9 (202608031930), 74 Logiktests und 12 von 15
UI-/Launch-Tests sind erfolgreich; drei echte Netz-/Auth-E2E-Tests wurden ohne
produktive Zugangsdaten/QR erwartungsgemäß übersprungen. Reale Kamera-
/Nivellierungstests, produktives TURN sowie die vollständige Netzwerk-/Cloud-
E2E-Matrix sind weiterhin offen. Sechs Strict-Concurrency-Warnungen im
`CameraManager` sind dokumentierte, nicht kaschierte Restarbeit.

## Bewusst nicht als erledigt behauptet

- Der v1-Paketvertrag verwendet weiterhin eine zusammenhängende AES-GCM-
  Envelope. Pro Datei wurden speicherschonendes Mapping und ein
  `autoreleasepool` ergänzt; ein echtes Streaming-/Chunk-Protokoll wäre eine
  inkompatible Protokollmigration und ist nicht Teil dieses Commits.
- Die releasekritischen Kamera-, Upload-, Auth- und Berechtigungspfade wurden
  lokalisiert. Die gesamte historisch gewachsene App ist damit noch nicht von
  jedem hart codierten sichtbaren Text bereinigt.
- Die sehr großen SwiftUI-Views und der `CameraManager` wurden nicht allein zur
  Verkürzung in viele Dateien zerlegt. Diese strukturelle Arbeit soll getrennt
  und mit echten Kamera-/Upload-Regressionstests erfolgen.
- Das Browser-Gegenstück gehört zum getrennten Web-Repository und ist deshalb
  nicht Bestandteil dieses ausdrücklich auf die Swift-App begrenzten
  Prüfrepositories. Der Swift-Vertrag darf trotzdem nur ein exakt passendes
  Receipt akzeptieren; ein Browser ohne diesen Vertrag muss sichtbar
  fehlschlagen und darf keinen lokalen Erfolgsstatus erzeugen.
