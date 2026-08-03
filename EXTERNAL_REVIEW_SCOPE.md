# PIXCAPTURE iOS — externer Prüfstand

`main` ist der vollständige aktuelle Prüfstand vom 3. August 2026. Es gibt
keinen getrennten Zukunfts- oder Kandidatenstand mehr.

## Herkunft und Isolation

- Aktueller lokaler Swift-Stand:
  `3e56988ad081ab006d25edf88e560c49193c6237`
- Öffentlicher Prüfstand nach Übernahme auf `main`: siehe aktuelle HEAD-ID
- Ursprünglicher App-Store-Ausgangsstand bleibt ausschließlich über den
  unveränderlichen Git-Tag `source-5f2fa402-ios-3.8` nachvollziehbar.
- Dieses Repository besitzt keinen Remote oder automatischen Weg zum privaten
  Produktions-Repository.

## Inhalt der aktuellen Änderungen

- cancellation-sicherer WebRTC-Timeout, Fehlerweitergabe und Cleanup
- Auswertung browserseitig gemeldeter Übertragungsfehler
- iPhone-Unterstützung für Portrait, Landscape Left und Landscape Right
- viewportbezogene Nivellierung ohne zweite Landschaftsachsen-Drehung
- Regressionstests für den beobachteten Fehlerwert `-89,8°`
- Fotografieren und lokale Speicherung ohne Anmeldung
- Freischaltung erst vor Servertransfer über zwei SMS-Stufen
- Upload-Login mit E-Mail-Adresse und selbst gewähltem Web-Passwort
- warmes kontrastreiches Greige statt orangefarbener Fließ-/Eingabetexte
- expliziter UI-Test für Scrollbarkeit und untere Safe Area

## Nachweisstand

Simulatorbuild, signierter iPhone-Build, 66 Unit-/Integrationstests und der
gezielte Erststart-UI-Test sind erfolgreich. Reale Kamera-/Nivellierungstests
auf dem iPhone sowie die vollständige Netzwerk-/Cloud-E2E-Matrix sind weiterhin
offen und in der Release-Prüfliste ausdrücklich markiert.
