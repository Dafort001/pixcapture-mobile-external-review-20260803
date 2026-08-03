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
- Swift und Browser können eine gemeinsame ICE-Konfiguration mit STUN und
  optionalen kurzlebigen coturn-REST-Zugangsdaten beziehen. Ein produktiver
  TURN-Dienst ist noch nicht provisioniert und in getrennten Netzen
  nachgewiesen; eine netzunabhängige Erfolgsgarantie besteht deshalb nicht.
- Browser-Companion und lokaler Receiver dürfen Erfolg nur mit exakt passender
  Paket-ID, Bytezahl und SHA-256 bestätigen. Warnungen oder unvollständige
  Receipts sind Fehler und dürfen lokale Records nicht auf `uploaded` setzen.

## Kamera und Orientierung

- iPhone unterstützt Portrait, Landscape Left und Landscape Right.
- Die Bedienoberfläche und Vorschau bleiben aus UX-Gründen portraitfixiert.
  Nivellierung und Aufnahme-/EXIF-Orientierung müssen davon getrennt die aus
  CoreMotion-Schwerkraft bestimmte physische Gerätehaltung verwenden. Eine
  weiterhin als Portrait gemeldete Scene darf beim Drehen des Telefons nicht
  erneut den beobachteten 90-Grad-Fehler erzeugen.
- Bereits viewportbezogene Roll-/Pitch-Werte dürfen im Single-Shot-Pfad nicht
  ein zweites Mal um die Landschaftsachse gedreht werden.
- Der reproduzierte Fehler war: gleiche physische Lage, Portrait `R 0,0° / P
  1,2°`, Landscape `R -89,8° / P 0,7°`.

## Bedienbarkeit und Barrierearmut

- Fließ- und Eingabetext auf schwarzem Hintergrund verwendet kontrastreiches
  warmes Greige. Numerische Levelwerte sind hellblau; Rot/Grün darf Information
  nicht allein tragen. Orange bleibt Akzent.
- Der lange Erststart muss vollständig scrollbar sein. Die letzte Aktion muss
  oberhalb der unteren Safe Area erreichbar bleiben.
- Die Kamera-Berechtigung darf nicht vor der bewussten Auswahl einer
  Kamerafunktion erscheinen.

## Freigabegrenze

- Build- und Unit-Test-Erfolg allein ist keine App-Store-Freigabe.
- Beide physischen Querformatrichtungen sind für Nivellierung und reale
  DNG-/EXIF-Aufnahmen auf einem iPhone 15 Pro Max nachgewiesen. Vor einer
  Veröffentlichung bleiben eine neue Portraitaufnahme, Galerie-/Exportprüfung,
  Grundriss-Textabgleich sowie WebRTC-/Cloud-End-to-End-Läufe einschließlich
  Fehler, Retry, großem Paket und Datenintegritätsabgleich verpflichtend.
