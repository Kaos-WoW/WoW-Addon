# Loot-Ordnung — Changes Log

## 24.09.2026 — Portierung nach WoW Forever (Classic+)
- Erstellung `CHANGES_LOG.md`, `WORKBOARD.md` und `deploy-forever.ps1`.
- `LootOrdnung.toc`: Erweiterung der Interface-Nummern um 16001, 120100, 120105.
- `Gilde.lua`: `Gilde.Lesen()` dahingehend angepasst, dass in Forever die primäre `C_Club`-API vor dem Legacy-Fallback `GetGuildRosterInfo` abgefragt wird.
- `Gilde.lua`: Schreibwarteschlange von `C_Timer.After` auf einen unkontaminierten `OnUpdate`-Frame umgestellt, um `ADDON_ACTION_FORBIDDEN`-Taint durch Chat-EditBox / KaosUI bei `C_GuildInfo.SetNote` zu verhindern.
- `Fenster.lua`: `SetScript("OnDragStart")` & `OnDragStop` korrigiert (Methoden-Referenz in anonyme Funktion gewickelt).
- **Messungen im Spiel:**
  - Messpunkt 1: 102/102 Tests bestanden.
  - Messpunkt 2: `sehen: true`, `schreiben: true`. Offiziersnotiz ist nicht *secret*. Architektur ist tragfähig!
  - Messpunkt 3: Gilden-Roster-Abfrage über `ns.Gilde.Lesen()` erfolgreich.
  - ✅ Messpunkt 4: Option 1 erfolgreich umgesetzt — Offiziersnotizen werden automatisch ausgelesen und über den Notiz-Assistenten geschrieben.
  - `Fenster.lua`: `SetScript("OnFocusGained")` auf `OnEditFocusGained` korrigiert (in WoW EditBoxes existiert kein `OnFocusGained`, was zuvor zu `bad argument #2 to '?'` beim Öffnen führte), `OnEscapePressed` und Close-Button-Handler ergänzt.
