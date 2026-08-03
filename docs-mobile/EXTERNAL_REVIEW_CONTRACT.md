# PIXCAPTURE iOS — verbindlicher externer Prüfvertrag

Stand: 2026-08-03

Diese Datei enthält den für die Swift-Codeprüfung nötigen Produkt- und
Sicherheitsvertrag. Externe Dateien sind dafür nicht erforderlich.

## Nutzung und Anmeldung

- Fotografieren, Grundrisse und lokale Speicherung funktionieren ohne Konto
  und ohne Anmeldung.
- Erst eine Serverübertragung benötigt einen freigeschalteten Zugang oder
  einen gültigen, serverseitig ausgestellten Übertragungs-QR.
- Registrierung: Mobilnummer, E-Mail-Adresse und selbst gewähltes Passwort auf
  PIXCAPTURE.APP; erster sechsstelliger SMS-Code bestätigt die Mobilnummer;
  persönliche Freigabe; zweite SMS bestätigt die Freigabe; Upload-Login in der
  App anschließend mit E-Mail-Adresse und Passwort.
- Die sichtbare Aktivierungserklärung darf keinen per E-Mail versandten
  Freischaltcode behaupten.

## Lokale Daten und Upload

- Originale dürfen bei Verbindungsfehler, Abbruch, Timeout oder fehlender
  Serverbestätigung nicht als übertragen markiert oder gelöscht werden.
- Ein Upload gilt erst nach vollständiger, überprüfbarer Gegenbestätigung als
  abgeschlossen.
- Fehlgeschlagene Übertragungen müssen sichtbar enden und wiederholbar bleiben;
  ein dauerhafter Zustand „Upload läuft / 0 KB“ ist unzulässig.
- Normale Wege sind Browser-Companion im lokalen Netz und Direkt-in-die-Cloud.
  Kabel ist nur ein nachrangiger Notfallweg.
- Der Browser-Companion verwendet derzeit STUN ohne produktiv nachgewiesenen
  TURN-Relay-Fallback. Ein sauber gemeldeter Fehler ist implementiert; eine
  netzunabhängige Erfolgsgarantie besteht deshalb ausdrücklich nicht.

## Kamera und Orientierung

- iPhone unterstützt Portrait, Landscape Left und Landscape Right.
- Kamera-Vorschau, Nivellierung, Keystone-Korrektur, Aufnahme und gespeicherte
  Pixel-/EXIF-Orientierung müssen dieselbe aktive Viewport-Orientierung
  verwenden.
- Bereits viewportbezogene Roll-/Pitch-Werte dürfen im Single-Shot-Pfad nicht
  ein zweites Mal um die Landschaftsachse gedreht werden.
- Der reproduzierte Fehler war: gleiche physische Lage, Portrait `R 0,0° / P
  1,2°`, Landscape `R -89,8° / P 0,7°`.

## Bedienbarkeit und Barrierearmut

- Fließ- und Eingabetext auf schwarzem Hintergrund verwendet kontrastreiches
  warmes Greige. Orange bleibt Akzent und darf Information nicht allein
  tragen.
- Der lange Erststart muss vollständig scrollbar sein. Die letzte Aktion muss
  oberhalb der unteren Safe Area erreichbar bleiben.
- Die Kamera-Berechtigung darf nicht vor der bewussten Auswahl einer
  Kamerafunktion erscheinen.

## Freigabegrenze

- Build- und Unit-Test-Erfolg allein ist keine App-Store-Freigabe.
- Vor einer Veröffentlichung bleiben die realen iPhone-Nachweise für beide
  Querformatrichtungen sowie WebRTC-/Cloud-End-to-End-Läufe einschließlich
  Fehler, Retry, großem Paket und Datenintegritätsabgleich verpflichtend.
