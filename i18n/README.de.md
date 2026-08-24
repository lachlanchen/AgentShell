[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# AgentShell

*Getrennte AI-CLI-Konten in verschiedenen Terminals mit einem gemeinsamen echten Arbeitsbaum.*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](../LICENSE)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](../docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)

AgentShell ermöglicht persönliche, Labor- und Firmen-Terminals mit unterschiedlichen Codex-Anmeldungen, ohne Projekte zu kopieren, Unix-Benutzer zu wechseln oder Container zu pflegen. Jeder Prozess bleibt im aktuellen Verzeichnis; offiziell unterstützte Umgebungsvariablen leiten nur Authentifizierung und Zustand in ein benanntes Profil.

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## Kernfunktionen

- Eigenständige Codex-Authentifizierung und Provider-Zustände für jedes Label.
- Optional gemeinsamer Verlauf, ohne Anmeldedaten zu vermischen.
- Keine Kopien des Arbeitsbereichs: Git, Conda, Werkzeuge und Dateien bleiben am Platz.
- Native Argumente, Modelle, Prompts, Bilder und künftige CLI-Optionen werden weitergereicht.
- `codexr`, `/rename`, Teilpfadsuche und `codexmv` bleiben erhalten.
- Codex ist vollständig integriert; Claude Code, Gemini CLI und Copilot CLI erhalten Zustandsadapter.

## Schnellstart

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

Für entfernte oder Headless-Anmeldungen:

```bash
codex --account personal login --device-auth
```

Das [vollständige Tutorial](../docs/tutorial.md) behandelt Installation, Browser-Anmeldung, Kontowechsel, privaten/geteilten Verlauf, Wiederaufnahme, Migration und Fehlerbehebung.

## Tägliche Nutzung

```bash
source ~/.bashrc
agentshell personal
codexr
```

Die AgentShell-Option `--account` muss zuerst stehen. Ohne Kontooption behalten `codex`, `codexr` und `codexmv` ihr gewohntes Verhalten.

## Private Anmeldedaten, wählbarer Verlauf

| Modus | Anmeldedaten | SQLite-Wiederaufnahmeindex | Empfohlene Nutzung |
|---|---|---|---|
| `private` | Profilintern | Profilintern | Vertrauliche Labor- oder Firmenarbeit |
| `shared` | Profilintern | Gemeinsamer Basisindex | Gleiche Sitzungen mit mehreren Konten fortsetzen |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

AgentShell nutzt die öffentlich dokumentierte Trennung von `CODEX_HOME` und `CODEX_SQLITE_HOME`. Anmeldedaten werden niemals nur zum Teilen des Wiederaufnahmekatalogs freigegeben.

## Repository-Übersicht

| Pfad | Zweck |
|---|---|
| [bin/agentshell](../bin/agentshell) | Profil-Laufzeit und Befehlsverteiler |
| [shell/agentshell.bash](../shell/agentshell.bash) | Bash-Integration für Kontoargumente |
| [install.sh](../install.sh) | Idempotenter Installer für den aktuellen Benutzer |
| [docs/tutorial.md](../docs/tutorial.md) | Vollständige Anleitung von Anfang bis Ende |
| [docs/architecture.md](../docs/architecture.md) | Zustandsgrenzen und Sicherheitsdesign |
| [docs/providers.md](../docs/providers.md) | Adapter der verschiedenen AI-CLIs |
| [tests/test.sh](../tests/test.sh) | Isolierte Integrationstests |

## Validierung

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

## Sicherheitsumfang

Profilverzeichnisse, `auth.json`, Token, Cookies, SQLite-Datenbanken und private Umgebungsdateien dürfen nicht committed werden. Profile mit gemeinsamem Verlauf sehen indexierte Titel, Vorschauen und Pfade. AgentShell ist für denselben vertrauenswürdigen Unix-Benutzer gedacht und bietet keine Sicherheitsisolierung auf Betriebssystemebene.

## Zitation

Wenn AgentShell in Forschung oder Werkzeugen verwendet wird, zitieren Sie dieses Repository. GitHub liest [CITATION.cff](../CITATION.cff) und zeigt den Bereich **Cite this repository** an.

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## Status und Lizenz

AgentShell ist ein aktiv gepflegtes, abhängigkeitsarmes Bash-Werkzeug. Codex ist die primäre geprüfte Integration; andere Adapter folgen den öffentlichen Zustandsverzeichnis-Mechanismen ihrer Werkzeuge. Veröffentlicht unter der [MIT-Lizenz](../LICENSE).

