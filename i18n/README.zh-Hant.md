[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# AgentShell

*讓不同終端使用不同的 AI CLI 帳號，同時共享同一個真實工作目錄。*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](../LICENSE)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](../docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)

AgentShell 讓個人、實驗室與公司終端分別使用獨立的 Codex 登入，而不複製專案、不更換 Unix 使用者，也不需要維護容器。程序始終位於目前目錄，AgentShell 只透過工具正式支援的環境變數，將驗證與狀態導向具名設定檔。

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## 核心能力

- 每個標籤都有獨立的 Codex 驗證與供應商狀態。
- 驗證保持分離時，仍可選擇共享同一個 Codex 工作階段索引。
- 不複製工作區；Git、Conda、建置工具與檔案都留在原位。
- 原生參數、模型、提示、圖片及未來 CLI 選項都會繼續傳遞。
- 保留工作站的 `codexr`、`/rename`、路徑搜尋與 `codexmv` 流程。
- Codex 已完整整合，並為 Claude Code、Gemini CLI 與 Copilot CLI 提供狀態介接。

## 快速開始

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

遠端或無圖形介面的登入可使用：

```bash
codex --account personal login --device-auth
```

安裝、瀏覽器登入、帳號切換、共享/私有歷史、恢復工作階段與疑難排解，請閱讀[完整教學](../docs/tutorial.md)。

## 日常使用

```bash
codex --account personal
codex --account lab -m gpt-5.6-sol "Review this repository"
codexr --account company --all

cd /path/to/project
agentshell lab
agentshell -v
codex
codexr
exit
```

AgentShell 的 `--account` 必須放在最前面。沒有帳號選項的 `codex`、`codexr` 與 `codexmv` 會維持原本行為。

## 私有驗證與可選歷史

| 模式 | 驗證 | SQLite 恢復索引 | 建議用途 |
|---|---|---|---|
| `private` | 設定檔內私有 | 設定檔內私有 | 需要保密隔離的實驗室或公司工作 |
| `shared` | 設定檔內私有 | 共享基礎索引 | 從多個帳號恢復同一工作站的工作階段 |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

AgentShell 使用 Codex 正式提供的 `CODEX_HOME` 與 `CODEX_SQLITE_HOME` 邊界：可以共享恢復目錄，但不會因此共享登入憑證。

## 儲存庫結構

| 路徑 | 用途 |
|---|---|
| [bin/agentshell](../bin/agentshell) | 設定檔執行階段與命令分派器 |
| [shell/agentshell.bash](../shell/agentshell.bash) | Bash 帳號參數整合 |
| [install.sh](../install.sh) | 可重複執行的使用者級安裝程式 |
| [docs/tutorial.md](../docs/tutorial.md) | 從安裝到排錯的完整教學 |
| [docs/architecture.md](../docs/architecture.md) | 狀態邊界與安全設計 |
| [docs/providers.md](../docs/providers.md) | 各 AI CLI 的介接說明 |
| [tests/test.sh](../tests/test.sh) | 隔離整合測試 |

## 驗證

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

## 安全範圍

請勿提交設定檔目錄、`auth.json`、權杖、Cookie、SQLite 資料庫或私有環境檔。共享歷史會讓參與設定檔看到索引中的標題、預覽與路徑。AgentShell 服務於同一位可信的 Unix 使用者，不是作業系統級安全隔離。

## 引用

若在研究或工具鏈中使用 AgentShell，請引用本儲存庫。GitHub 會讀取 [CITATION.cff](../CITATION.cff) 並顯示 **Cite this repository** 面板。

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## 狀態與授權

AgentShell 是持續維護、相依性極少的 Bash 工具。Codex 是主要且已驗證的整合，其他介接遵循各工具公開的狀態目錄機制。專案採用 [MIT License](../LICENSE)。

