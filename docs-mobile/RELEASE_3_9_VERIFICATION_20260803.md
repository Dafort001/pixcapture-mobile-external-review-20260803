# PixCapture Mobile 3.9 – verbindliche Release-Prüfung

Status: Arbeitsgrundlage, noch keine Freigabe
Basis: App-Store-Version 3.8 / Build 202607172137

Eine neue Apple-Einreichung ist erst zulässig, wenn alle Pflichtnachweise unten
mit Datum, Gerät, iOS-Version und Ergebnis dokumentiert sind. Ein erfolgreicher
Build ersetzt keinen realen Geräte- oder Übertragungstest.

## Bereits lokal nachgewiesen

- [x] Debug-Simulatorbuild ohne ausgelagertes OpenCV-Framework erfolgreich.
- [x] Erzeugtes App-Bundle enthält Portrait, Landscape Left und Landscape Right
  als unterstützte iPhone-Ausrichtungen.
- [x] App-Store-3.8-Fehler anhand Daniels Screenshots reproduziert: Portrait
  `R 0,0° / P 1,2°`, Landscape in gleicher Lage `R -89,8° / P 0,7°`.
- [x] 63 Unit-/Integrationstests erfolgreich, einschließlich fünf neuer
  Level-/Querformat-Regressionstests und vorhandener Galerie-Orientierungstests.
- [x] Signierter Debug-Build für Daniels verbundenes iPhone 15 Pro Max
  erfolgreich; noch nicht installiert.
- [ ] Vollständige UI-Suite: ein bestehender Galerie-Test benötigt Testdaten;
  drei echte Upload-E2E-Tests wurden ohne Zugangsdaten/QR-Payload übersprungen.

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
