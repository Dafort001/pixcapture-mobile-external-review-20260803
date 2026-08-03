# PixCapture Mobile 3.9 – verbindliche Release-Prüfung

Status: Arbeitsgrundlage, noch keine Freigabe
Basis: App-Store-Version 3.8 / Build 202607172137

Eine neue Apple-Einreichung ist erst zulässig, wenn alle Pflichtnachweise unten
mit Datum, Gerät, iOS-Version und Ergebnis dokumentiert sind. Ein erfolgreicher
Build ersetzt keinen realen Geräte- oder Übertragungstest.

## Bereits lokal nachgewiesen

- [x] Debug-Simulatorbuild und generischer Release-Gerätebuild ohne
  ausgelagertes OpenCV-Framework erfolgreich. Das Release-Bundle meldet
  Version `3.9`, Build `202608031930`, Architektur `arm64`.
- [x] Erzeugtes App-Bundle enthält Portrait, Landscape Left und Landscape Right
  als unterstützte iPhone-Ausrichtungen.
- [x] App-Store-3.8-Fehler anhand Daniels Screenshots reproduziert: Portrait
  `R 0,0° / P 1,2°`, Landscape in gleicher Lage `R -89,8° / P 0,7°`.
- [x] 74 Unit-/Integrations-/Logiktests erfolgreich, einschließlich neuer
  Level-/Querformat-, Browser-ACK-, Companion-Receipt-, Kontrast- und
  SMS-Aktivierungstests in Deutsch und Englisch.
- [x] Gezielter Erststart-UI-Test erfolgreich: Ohne Anmeldung bis zum lokalen
  Startbildschirm; keine Kamera-Berechtigungsabfrage vor der bewussten
  Kamerawahl; vollständiger Textbereich bis zur letzten Aktion scrollbar und
  untere Aktion oberhalb der Safe Area erreichbar.
- [x] Erststart im Simulator visuell geprüft: Offline-Fotografie steht an
  erster Stelle, beide SMS-Stufen sind erklärt, und Fließtext auf Schwarz nutzt
  kontrastreiches warmes Greige statt Orange.
- [x] Der gesicherte Seeburg-Testbestand wurde nur in einen iPhone-17-Pro-
  Simulator zurückgespielt. Der Galerie-Upload-UI-Test wählt eine echte Serie,
  öffnet den Uploaddialog und bestätigt, dass Companion und Cloud sichtbar
  sind und der Companion-Start vor QR-Kopplung deaktiviert bleibt.
- [x] Vollständiger Simulator-Testlauf: 86 Tests bestanden; drei echte
  Netz-/Authentifizierungs-E2E-Szenarien wurden ohne produktive Zugangsdaten
  beziehungsweise QR-Payload erwartungsgemäß übersprungen.
- [x] Der lokale Companion-Receiver nahm das reale Seeburg-Paket mit exakt
  1.849.171.856 Byte und korrektem SHA-256 an. Ein absichtlich falscher Hash
  ergab HTTP 422; keine beschädigte Zieldatei blieb zurück.
- [x] Browser-Gegenstück: fünf Receipt-/ICE-Konfigurationstests sowie
  TypeScript-Typprüfung erfolgreich.
- [x] Signierter Debug-Build für Daniels verbundenes iPhone 15 Pro Max
  erfolgreich; bewusst noch nicht installiert, damit dessen Kundendaten nicht
  berührt werden.

## Noch nicht als produktionsreif nachgewiesen

- Die Orientierungsrechnung und die beiden Querformatdeklarationen sind im
  Code und durch Regressionstests korrigiert. Das sichtbare grüne Quadrat muss
  dennoch auf einem echten iPhone in Portrait, Landscape Left und Landscape
  Right nachgewiesen werden.
- Der WebRTC-Vertrag wartet jetzt auf eine exakte Browserbestätigung aus
  Paket-ID, Bytezahl und SHA-256 und beendet Fehler/Timeouts statt bei 0 KB zu
  hängen. Ein produktiver TURN-Dienst ist jedoch noch nicht provisioniert;
  netzübergreifende Zuverlässigkeit darf deshalb noch nicht zugesagt werden.
- Uploads sind bewusst Vordergrundübertragungen. Beim Sperren oder Verlassen
  der App wird der aktive Versuch abgebrochen und bleibt wiederholbar; ein
  echter iOS-Hintergrundupload ist nicht implementiert.
- Swift Strict Concurrency (`targeted`) ist aktiv. Der Release-Build hat noch
  sechs bekannte Warnungen im historisch gewachsenen `CameraManager`; deren
  strukturelle Actor-Isolation ist eine eigene, realgerätepflichtige Arbeit
  und wurde nicht mit `nonisolated(unsafe)` kaschiert.

## Pflichtnachweis A – Kamera und Nivellierung auf echtem iPhone

- [ ] Portrait: Anzeige wird bei waagerechtem Gerät grün; Screenshot und
  angezeigte Gradwerte sichern.
- [ ] Landscape Left: gleicher Nachweis.
- [ ] Landscape Right: gleicher Nachweis.
- [ ] Je Ausrichtung mindestens eine reale Aufnahme erzeugen.
- [ ] Dateien in Galerie, Export und auf einem zweiten Gerät öffnen und auf
  korrekte Pixel-/EXIF-Orientierung prüfen.
- [ ] Vorschau, Bedienelemente, Safe Areas und Rotation während einer laufenden
  Kamerasitzung prüfen.

## Pflichtnachweis B – Browser-Companion/WebRTC

- [ ] Erfolgsfall im gleichen WLAN mit kleinem Paket: Datenkanal öffnet, Bytes
  steigen, Browser bestätigt Empfang, App markiert erst danach als übertragen.
- [ ] Erfolgsfall mit repräsentativ großem Paket.
- [ ] Erzwungener ICE-Fehler: App beendet den Versuch spätestens nach dem
  Timeout, zeigt einen Fehler statt dauerhaft „Upload läuft / 0 KB“ und lässt
  alle Originale auf `pending`/wiederholbar.
- [ ] Browserseitiger Abbruch wird in der App als Fehler übernommen.
- [ ] Wiederholung nach Fehler überträgt genau einmal und erzeugt keine
  Duplikate.
- [ ] Wechsel WLAN/Mobilfunk, App-Hintergrund und gesperrtes Display jeweils
  kontrolliert prüfen.
- [ ] TURN-/Relay-Fallback auf beiden Seiten produktiv konfigurieren und in
  getrennten Netzen testen; bis dahin darf WebRTC nicht als netzunabhängig
  garantiert werden.

## Pflichtnachweis C – alternative Uploadwege und Datenintegrität

- [ ] Frische Installation: ohne Registrierung fotografieren und Aufnahmen
  nach App-Neustart weiterhin lokal vollständig vorfinden.
- [ ] Erst beim Übertragungsversuch anmelden beziehungsweise einen gültigen
  serverseitigen Übertragungs-QR verwenden; ohne Freigabe keine Serverdaten
  erzeugen und keine lokalen Dateien verlieren.
- [ ] Direkt-in-die-Cloud mit 3er-DNG-Serie vollständig.
- [ ] Direkt-in-die-Cloud mit 5er-DNG-Serie vollständig.
- [ ] Offline aufnehmen, später übertragen.
- [ ] Abbruch und Wiederaufnahme ohne Doppelregistrierung.
- [ ] Zwei Aufträge am selben Tag wechseln; keine falsche Zuordnung.
- [ ] Lokale Dateizahl, Manifest, Browser/Cloud-Eingang und Jobstatus stimmen
  exakt überein.

## Freigabeprotokoll

Für jeden Lauf festhalten:

- Datum/Uhrzeit, App-Commit und Buildnummer
- iPhone-Modell und iOS-Version
- Browser, Rechner und Netzkonstellation
- Auftrag/Session und erwartete Motiv-/Datei-/Bytezahl
- tatsächliches Ergebnis, Screenshots und relevante App-/Browserlogs
- verbliebene lokale Records sowie Remote-Dateien/Jobstatus

Freigabe für TestFlight/App Store erst nach Daniels ausdrücklicher Zustimmung
auf Grundlage dieses vollständig ausgefüllten Protokolls.
