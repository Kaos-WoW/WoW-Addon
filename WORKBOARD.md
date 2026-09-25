# Loot-Ordnung — Workboard

## Dateibelegung / File Locks
- `CHANGES_LOG.md`: Antigravity Agent
- `WORKBOARD.md`: Antigravity Agent
- `LootOrdnung/`: Antigravity Agent (Abarbeitung Messplan Forever-Port)

## Aktueller Status
- Portierung nach WoW Forever (Classic+):
  - ✅ Messpunkt 1 (Ladefähigkeit / `/lo test`): 102/102 Prüfungen bestanden.
  - ✅ Messpunkt 2 (Rechte & Secret-Status): `sehen: true`, `schreiben: true`, Notiz lesbar. Architektur bestätigt!
  - ✅ Messpunkt 3 (Roster & `C_Club`-Fallback): Funktioniert.
  - ✅ Messpunkt 4 (Option 1 umgesetzt): Notiz-Assistent (`Fenster.lua`) erstellt. Konten werden vollautomatisch gelesen (`C_Club.GetMemberInfo`). Zum Schreiben berechnet das Addon den Notiz-String (z. B. `LO:50,100,2960,0,0,0`) und stellt ihn im Assistenten mit 1-Klick-Fokus & Strg+C bereit, um ihn in Blizzards Gildenfenster zu übernehmen.
