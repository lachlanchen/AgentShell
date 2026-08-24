[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# AgentShell

*让不同终端使用不同的 AI CLI 账号，同时共享同一个真实工作目录。*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](../LICENSE)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](../docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)

AgentShell 让个人、实验室和公司终端分别使用独立的 Codex 登录，而不复制项目、不更换 Unix 用户，也不需要维护容器。进程始终停留在当前目录中，AgentShell 只通过工具官方支持的环境变量，把认证和状态路由到具名配置中。

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## 核心能力

- 每个标签拥有独立的 Codex 认证和提供商状态。
- 可在认证保持分离的同时，共享一个 Codex 会话索引。
- 不复制工作区；Git、Conda、构建工具和文件都保持原位。
- 原生参数、模型、提示词、图片和未来的 CLI 选项会继续传递。
- 保留工作站上的 `codexr`、`/rename`、路径搜索和 `codexmv` 工作流。
- Codex 已完整集成，并为 Claude Code、Gemini CLI 与 Copilot CLI 提供状态适配。

## 快速开始

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

远程或无界面登录可使用：

```bash
codex --account personal login --device-auth
```

安装、浏览器登录、账号切换、共享/私有历史、恢复会话和故障排查，请阅读[完整教程](../docs/tutorial.md)。

## 日常使用

```bash
source ~/.bashrc
agentshell personal
codexr
```

AgentShell 的 `--account` 必须放在最前面。不带账号选项的 `codex`、`codexr` 和 `codexmv` 保持原有行为。

## 私有认证与可选历史

| 模式 | 认证 | SQLite 恢复索引 | 适用场景 |
|---|---|---|---|
| `private` | 配置内私有 | 配置内私有 | 需要保密隔离的实验室或公司工作 |
| `shared` | 配置内私有 | 共享基础索引 | 用多个账号恢复同一工作站会话 |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

AgentShell 利用 Codex 官方的 `CODEX_HOME` 与 `CODEX_SQLITE_HOME` 边界：可以共享恢复目录，但绝不会因此共享登录凭据。

## 仓库结构

| 路径 | 用途 |
|---|---|
| [bin/agentshell](../bin/agentshell) | 配置运行时和命令分发器 |
| [shell/agentshell.bash](../shell/agentshell.bash) | Bash 账号参数集成 |
| [install.sh](../install.sh) | 可重复执行的用户级安装器 |
| [docs/tutorial.md](../docs/tutorial.md) | 从安装到排错的完整教程 |
| [docs/architecture.md](../docs/architecture.md) | 状态边界与安全设计 |
| [docs/providers.md](../docs/providers.md) | 各 AI CLI 的适配说明 |
| [tests/test.sh](../tests/test.sh) | 隔离集成测试 |

## 验证

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

## 安全范围

不要提交配置目录、`auth.json`、令牌、Cookie、SQLite 数据库或私有环境文件。共享历史会让参与的配置看到索引中的标题、预览和路径。AgentShell 面向同一个可信 Unix 用户，不是操作系统级安全隔离。

## 引用

如果 AgentShell 用于研究或工具链，请引用本仓库。GitHub 会读取 [CITATION.cff](../CITATION.cff) 并显示 **Cite this repository** 面板。

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## 状态与许可

AgentShell 是持续维护、依赖极少的 Bash 工具。Codex 是主要的已验证集成，其他适配器遵循各工具公开的状态目录机制。项目采用 [MIT License](../LICENSE)。

