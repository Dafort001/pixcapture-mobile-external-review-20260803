# PIXCAPTURE iOS 3.9 – öffentlicher Code-Prüfstand

Dieses öffentliche Repository ist eine isolierte, vollständige Kopie des
aktuellen Swift-App-Standes. Änderungen hier wirken sich nicht auf das private
Produktions-Repository oder die App-Store-Version aus.

## Einstieg für die externe Prüfung

1. `EXTERNAL_REVIEW_SCOPE.md`
2. `docs-mobile/EXTERNAL_REVIEW_CONTRACT.md`
3. `docs-mobile/RELEASE_3_9_VERIFICATION_20260803.md`
4. Swift-Code und Tests unter `ios/`

Interne Handovers oder Dateien außerhalb dieses Repositories sind für die
Prüfung weder erforderlich noch maßgeblich.

## Inhalt

- `ios/PIXCAPTURE/`: App-Quellcode
- `ios/PIXCAPTURETests/`: Unit-, Integrations- und Regressionstests
- `ios/PIXCAPTUREUITests/`: UI- und Launchtests
- `scripts/`: lokaler, gepaarter Companion-Receiver und Release-Prüfskript
- `docs-mobile/`: aktueller Prüfvertrag und Release-Testmatrix

Der Prüfstand basiert auf dem privaten Mobile-Commit
`685af1b1677e01147d35d68a51cf391b52c5793e`. Er ist ein überprüfter
Entwicklungskandidat, aber ausdrücklich noch keine App-Store-Freigabe: Die in
der Testmatrix aufgeführten echten iPhone-, AR-, TURN- und Upload-End-to-End-
Nachweise sind weiterhin offen.
