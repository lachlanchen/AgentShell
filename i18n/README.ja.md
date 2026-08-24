[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# AgentShell

*同じ実ワークツリーを共有しながら、端末ごとに異なる AI CLI アカウントを使う。*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](../LICENSE)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](../docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)

AgentShell を使うと、プロジェクトを複製したり Unix ユーザーを変更したり、コンテナを維持したりせずに、個人・研究室・会社の各端末で別々の Codex ログインを使えます。プロセスは現在のディレクトリに残り、各ツールが公式にサポートする環境変数だけで認証と状態を名前付きプロファイルへ振り分けます。

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## 主な機能

- ラベルごとに独立した Codex 認証とプロバイダー状態を保持します。
- 認証を分離したまま、Codex のセッション索引だけを共有できます。
- ワークスペースを複製せず、Git、Conda、ビルドツール、ファイルをそのまま使います。
- ネイティブの引数、モデル、プロンプト、画像、将来の CLI オプションを透過的に渡します。
- `codexr`、`/rename`、部分パス検索、`codexmv` の既存ワークフローを維持します。
- Codex を完全統合し、Claude Code、Gemini CLI、Copilot CLI にも状態アダプターを提供します。

## クイックスタート

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

リモートまたはヘッドレス環境では次を使います。

```bash
codex --account personal login --device-auth
```

インストール、ブラウザ認証、アカウント切替、共有/非公開履歴、再開、トラブルシューティングは[完全チュートリアル](../docs/tutorial.md)を参照してください。

## 日常的な使い方

```bash
source ~/.bashrc
agentshell personal
codexr
```

AgentShell の `--account` は必ず先頭に置きます。アカウント指定のない `codex`、`codexr`、`codexmv` の動作は変わりません。

## 非公開認証と選択可能な履歴

| モード | 認証 | SQLite 再開索引 | 推奨用途 |
|---|---|---|---|
| `private` | プロファイル内 | プロファイル内 | 機密性が必要な研究室・会社の作業 |
| `shared` | プロファイル内 | 基本索引を共有 | 複数アカウントから同じ端末のセッションを再開 |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

AgentShell は Codex が公開する `CODEX_HOME` と `CODEX_SQLITE_HOME` の境界を利用します。再開カタログを共有するためにログイン資格情報を共有することはありません。

## リポジトリ構成

| パス | 用途 |
|---|---|
| [bin/agentshell](../bin/agentshell) | プロファイル実行環境とコマンドディスパッチャー |
| [shell/agentshell.bash](../shell/agentshell.bash) | Bash のアカウント引数統合 |
| [install.sh](../install.sh) | 再実行可能なユーザー用インストーラー |
| [docs/tutorial.md](../docs/tutorial.md) | 導入から問題解決までの完全ガイド |
| [docs/architecture.md](../docs/architecture.md) | 状態境界と安全設計 |
| [docs/providers.md](../docs/providers.md) | 各 AI CLI アダプターの説明 |
| [tests/test.sh](../tests/test.sh) | 分離された統合テスト |

## 検証

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

## セキュリティ範囲

プロファイルホーム、`auth.json`、トークン、Cookie、SQLite データベース、非公開の環境ファイルをコミットしないでください。共有履歴を使うプロファイル同士では、索引内のタイトル、プレビュー、パスが見えます。AgentShell は同一の信頼できる Unix ユーザー向けであり、OS レベルの隔離ではありません。

## 引用

研究やツールで AgentShell を利用する場合は、このリポジトリを引用してください。GitHub は [CITATION.cff](../CITATION.cff) を読み取り、**Cite this repository** パネルを表示します。

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## 状態とライセンス

AgentShell は継続的に保守されている、依存関係の少ない Bash ユーティリティです。Codex が主要な検証済み統合で、その他のアダプターは各ツールの公開状態ディレクトリ機構に従います。[MIT License](../LICENSE) で提供されます。

