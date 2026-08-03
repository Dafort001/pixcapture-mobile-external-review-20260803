# PixCapture Mobile

Dieses Repo ist die native PixCapture iOS-App: Aufnahme, lokale Sicherheit,
QR/Web-Connect, Upload-Queue, Paket-/Kabel-Export, TestFlight und Apple-
Compliance.

## Aktueller Einstieg

Vor Projektarbeit nicht aus alten Mobile-Handovers rekonstruieren. Der aktuelle
verbindliche Einstieg ist:

1. [../../00_READ_FIRST_EVERY_SESSION.md](/Volumes/drive%201/PIXCAPTURE/00_READ_FIRST_EVERY_SESSION.md)
2. [../../docs/START.md](/Volumes/drive%201/PIXCAPTURE/docs/START.md)
3. [../../docs/HANDOVERS/README.md](/Volumes/drive%201/PIXCAPTURE/docs/HANDOVERS/README.md)
4. [../../docs/HANDOVERS/PIXCAPTURE_CURRENT_CONTRACT.md](/Volumes/drive%201/PIXCAPTURE/docs/HANDOVERS/PIXCAPTURE_CURRENT_CONTRACT.md)

Der Current Contract gewinnt gegen aeltere Dateien in `docs-mobile/`.

## Inhalt

- [ios](/Volumes/drive%201/PIXCAPTURE/projects/pixcapture-mobile/ios)
  Die eigentliche iPhone-App
- [backend](/Volumes/drive%201/PIXCAPTURE/projects/pixcapture-mobile/backend)
  Mobile Upload- und Session-Backend
- [docs-mobile](/Volumes/drive%201/PIXCAPTURE/projects/pixcapture-mobile/docs-mobile)
  Historische und thematische Mobile-Notizen. Nicht als Single Source of Truth
  verwenden.

## Status

Aktiver iOS-Branch laut aktuellem Contract:
`codex/20260417-mobile-branding-handover`.

Aktueller Apple-/Release-Kontext, Upload-Pfade, Naming-Regeln und offene
Pruefpunkte stehen im Current Contract im Root-Handover.

Bewusst lokal und nicht fuer Git gedacht:
- `backend/node_modules/`
- lokale `.env`-Dateien
- Xcode-Nutzerzustand wie `xcuserdata`
