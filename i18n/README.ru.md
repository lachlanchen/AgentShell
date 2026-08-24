[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# AgentShell

*Разные учётные записи AI CLI в отдельных терминалах с единым настоящим рабочим деревом.*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](../LICENSE)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](../docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)

AgentShell позволяет личному, лабораторному и корпоративному терминалам использовать разные входы Codex без копирования проектов, смены пользователя Unix и обслуживания контейнеров. Процесс остаётся в текущем каталоге, а поддерживаемые поставщиками переменные окружения направляют аутентификацию и состояние в именованный профиль.

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## Основные возможности

- Независимая аутентификация Codex и состояние поставщика для каждой метки.
- Необязательный общий индекс сессий при раздельных учётных данных.
- Никаких копий рабочей области: Git, Conda, инструменты сборки и файлы остаются на месте.
- Нативные аргументы, модели, запросы, изображения и будущие параметры CLI передаются без изменений.
- Сохраняются процессы `codexr`, `/rename`, частичного поиска пути и `codexmv`.
- Codex полностью интегрирован; для Claude Code, Gemini CLI и Copilot CLI предусмотрены адаптеры состояния.

## Быстрый старт

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

Для удалённого или безэкранного входа:

```bash
codex --account personal login --device-auth
```

[Полное руководство](../docs/tutorial.md) описывает установку, вход через браузер, переключение аккаунтов, частную/общую историю, продолжение сессий, миграцию и устранение неполадок.

## Повседневное использование

```bash
source ~/.bashrc
agentshell personal
codexr
```

Параметр AgentShell `--account` должен стоять первым. Без него `codex`, `codexr` и `codexmv` сохраняют обычное поведение.

## Частные учётные данные и выбираемая история

| Режим | Аутентификация | Индекс SQLite | Рекомендуемое применение |
|---|---|---|---|
| `private` | Внутри профиля | Внутри профиля | Конфиденциальная лабораторная или корпоративная работа |
| `shared` | Внутри профиля | Общий базовый индекс | Продолжение одних сессий из нескольких аккаунтов |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

AgentShell использует публично описанное разделение Codex между `CODEX_HOME` и `CODEX_SQLITE_HOME`. Учётные данные не открываются только ради общего каталога продолжения сессий.

## Карта репозитория

| Путь | Назначение |
|---|---|
| [bin/agentshell](../bin/agentshell) | Среда профилей и диспетчер команд |
| [shell/agentshell.bash](../shell/agentshell.bash) | Интеграция параметра аккаунта в Bash |
| [install.sh](../install.sh) | Идемпотентный пользовательский установщик |
| [docs/tutorial.md](../docs/tutorial.md) | Полное руководство от установки до устранения ошибок |
| [docs/architecture.md](../docs/architecture.md) | Границы состояния и проектирование безопасности |
| [docs/providers.md](../docs/providers.md) | Адаптеры различных AI CLI |
| [tests/test.sh](../tests/test.sh) | Изолированные интеграционные тесты |

## Проверка

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

## Границы безопасности

Не добавляйте в коммиты каталоги профилей, `auth.json`, токены, cookies, базы SQLite и частные файлы окружения. Профили с общей историей видят индексированные заголовки, превью и пути. AgentShell предназначен для одного доверенного пользователя Unix и не является изоляцией безопасности уровня ОС.

## Цитирование

Если AgentShell используется в исследовании или инструментах, процитируйте репозиторий. GitHub читает [CITATION.cff](../CITATION.cff) и показывает панель **Cite this repository**.

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## Состояние и лицензия

AgentShell — активно поддерживаемая Bash-утилита с минимальными зависимостями. Codex является основной проверенной интеграцией; остальные адаптеры следуют публичным механизмам каталогов состояния своих инструментов. Проект распространяется по [лицензии MIT](../LICENSE).

