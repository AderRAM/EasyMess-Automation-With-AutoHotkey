# Export-Dados-2.4

AutoHotkey v2 automation that drives a browser (Chrome preferred, Firefox fallback) through a web reporting system (Caxias do Sul RH — `admrh*.caxias`) and exports one report per month for a date range. Two flows share one browser window: **FAPS** (main window) and **e-Social** (Consultas Dinâmicas → Consulta Eventos, 4 portals).

## Run

- Requires **AutoHotkey v2.0** (`#Requires AutoHotkey v2.0`). Launch `Export-Dados-2.4.ahk` (double-click or via `AutoHotkey64.exe`). No build/test/lint step exists — verification is running the script against the live site.
- Script must be run from its own directory (`A_ScriptDir`); `#Include modulos\*.ahk` and `config_v3.ini`/`classe_atual.txt` are resolved relative to it.
- Before running: open Chrome/Firefox on the target page; set destination folder in the UI; apply Conta/Tipo Folha via the "Aplicar…" buttons.

## Hotkeys

- `F1` start/resume (dispatches to FAPS or e-Social by active tab), `F2` pause only, `F3` reset (restarts paused), `Esc` exit.
- `g_CicloEmExecucao` is a shared lock — FAPS and e-Social cannot run concurrently (same browser window).

## Architecture (modulos/)

- `Utilitarios.ahk` — page detection (`DetectarPagina` → PAGINA1/PAGINA2/CARREGANDO/SEM_LEITURA/DESCONHECIDA), waits, logging, Ctrl+F helpers, browser detection (Chrome > Firefox).
- `Pagina1.ahk` — fill filters + Executar; manual "Aplicar Conta/Tipo Folha".
- `Pagina2.ahk` — validate result count, export CSV, save file.
- `EntrePaginas.ahk` — `ProcessarCiclo` (FAPS).
- `ESocial.ahk` — `ProcessarCicloESocial` / `IniciarESocial` (reuses Pagina1/2).
- `Interface.ahk` — GUI, config (INI), history combos.

## State & config

- `config_v3.ini` — dates, entity, paths, last selections (sections `Config`, `ConfigES`, `Entidades`, `Classes`).
- `classe_atual.txt` — persisted file-name prefix (survives F3 reset). Loaded at startup into `prefix`.
- `prefix` format: FAPS `ENTIDADE_sufixoDaClasse_`; e-Social `CHAVEENTIDADE_`.

## Key constants / gotchas

- Delays: `delayCurto=100`, `delayMedio=800`, `delayLongo=1500` ms. Timeouts: `TIMEOUT_MAX_CARREGANDO_SEGUNDOS=60`.
- Tab counts driving navigation: `TABS_APOS_REFERENCIA=1`, `TABS_ENTRE_CAMPOS=2`, `TABS_APOS_EXECUTAR=0`, `TABS_APOS_VOLTAR=0`. Wrong values are the #1 cause of "ABORTADO - esperava PAGINA2/PAGINA1" log lines.
- `CARREGANDO` detected when page contains ≥2 "Executar" (threshold was 1; caused infinite loops). Do not lower to 1.
- Firefox closes Ctrl+F find bar with 7×Tab + Enter; Chrome uses Shift+Tab. Browser-specific code paths exist in `FecharBuscaCtrlF`.
- `DetectarPagina` uses clipboard capture (Ctrl+A/Ctrl+C) — focus trapped in a text box returns SEM_LEITURA; recovery via Ctrl+F is already handled.
- Never send a literal `Esc` from the script — `Esc` is the physical kill switch checked via `GetKeyState`; a sent Esc can terminate the script. Use the wrappers.
- FAS discontinued: no exports from 202604 onward (`ClassificarEntidade`/`ExecutarProcessamento` warn).
- RPC classes require entity = Prefeitura/FAS/Câmara (`DetectarGrupoRPC`); minimum result count not enforced for RPC but aborts on 0/-1. Non-RPC requires ≥20 results.
- Empty result page shows "Sem informações para serem listadas" and counts as 0 (not -1).
- e-Social creates per-cycle folder `pastaBase\MMAAAA\CONSULTA EVENTOS`.
- e-Social reapplies Conta every month (férias code changes by month); FAPS applies Conta once via UI.
- Account code lists and suffixes are defined in main file (`CLASSE_*`, `SUFIXO_*`, `ESOCIAL_CONTA_*`, `CodigosFeriasIPAMSaude`).
- `DefinirPausado` is the only writer of `g_Pausado` (keeps UI in sync).

## Logs

- `log_acoes.csv` — every action with timing (slow actions flagged LENTO).
- `log_ciclos_com_erro.csv` / `log_ciclos_com_erro_esocial.csv` — aborted cycles with reason + etapa. First place to look when diagnosing.

## Editing tips

- Page-navigation constants and delays live in the main file; tune there.
- Adding/changing account classes: edit `CLASSE_*`/`SUFIXO_*` (main file) and the dropdown list in `Interface.ahk` (`CLASSES_PADRAO`).
- Encoding: source contains accented Portuguese; keep as-is.
