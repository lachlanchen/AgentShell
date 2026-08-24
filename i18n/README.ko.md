[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# AgentShell

*하나의 실제 작업 트리를 공유하면서 터미널마다 다른 AI CLI 계정을 사용합니다.*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](../LICENSE)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](../docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)

AgentShell은 프로젝트 복사, Unix 사용자 변경, 컨테이너 유지 없이 개인·연구실·회사 터미널에서 서로 다른 Codex 로그인을 사용하게 해 줍니다. 프로세스는 현재 디렉터리에 그대로 있으며, 도구가 공식 지원하는 환경 변수를 통해 인증과 상태만 이름이 지정된 프로필로 라우팅합니다.

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## 핵심 기능

- 각 레이블에 독립적인 Codex 인증과 공급자 상태를 제공합니다.
- 인증을 분리한 채 하나의 Codex 세션 인덱스를 선택적으로 공유합니다.
- 작업 공간을 복사하지 않고 Git, Conda, 빌드 도구와 파일을 그대로 사용합니다.
- 네이티브 인수, 모델, 프롬프트, 이미지와 향후 CLI 옵션을 그대로 전달합니다.
- `codexr`, `/rename`, 부분 경로 검색과 `codexmv` 워크플로를 유지합니다.
- Codex를 완전히 통합하며 Claude Code, Gemini CLI, Copilot CLI용 상태 어댑터도 제공합니다.

## 빠른 시작

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

원격 또는 헤드리스 로그인에서는 다음을 사용합니다.

```bash
codex --account personal login --device-auth
```

설치, 브라우저 로그인, 계정 전환, 공유/비공개 기록, 세션 재개와 문제 해결은 [전체 튜토리얼](../docs/tutorial.md)을 참고하세요.

## 일상 사용

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

AgentShell의 `--account`는 항상 첫 번째에 있어야 합니다. 계정 옵션이 없는 `codex`, `codexr`, `codexmv`의 기존 동작은 바뀌지 않습니다.

## 비공개 인증과 선택 가능한 기록

| 모드 | 인증 | SQLite 재개 인덱스 | 권장 용도 |
|---|---|---|---|
| `private` | 프로필 내부 | 프로필 내부 | 기밀성이 필요한 연구실·회사 작업 |
| `shared` | 프로필 내부 | 기본 인덱스 공유 | 여러 계정에서 같은 워크스테이션 세션 재개 |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

AgentShell은 Codex가 공개한 `CODEX_HOME`과 `CODEX_SQLITE_HOME` 경계를 사용합니다. 재개 카탈로그를 공유하기 위해 로그인 자격 증명을 공유하지 않습니다.

## 저장소 구성

| 경로 | 목적 |
|---|---|
| [bin/agentshell](../bin/agentshell) | 프로필 런타임과 명령 디스패처 |
| [shell/agentshell.bash](../shell/agentshell.bash) | Bash 계정 인수 통합 |
| [install.sh](../install.sh) | 반복 실행 가능한 사용자 설치 프로그램 |
| [docs/tutorial.md](../docs/tutorial.md) | 설치부터 문제 해결까지의 전체 안내서 |
| [docs/architecture.md](../docs/architecture.md) | 상태 경계와 안전 설계 |
| [docs/providers.md](../docs/providers.md) | AI CLI 어댑터 설명 |
| [tests/test.sh](../tests/test.sh) | 격리된 통합 테스트 |

## 검증

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

## 보안 범위

프로필 홈, `auth.json`, 토큰, 쿠키, SQLite 데이터베이스 또는 비공개 환경 파일을 커밋하지 마세요. 공유 기록을 사용하는 프로필은 인덱스의 제목, 미리 보기와 경로를 서로 볼 수 있습니다. AgentShell은 동일한 신뢰 가능한 Unix 사용자를 위한 도구이며 OS 수준 보안 격리가 아닙니다.

## 인용

연구나 도구에서 AgentShell을 사용한다면 이 저장소를 인용해 주세요. GitHub는 [CITATION.cff](../CITATION.cff)를 읽어 **Cite this repository** 패널을 표시합니다.

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## 상태와 라이선스

AgentShell은 지속적으로 관리되는 의존성이 적은 Bash 유틸리티입니다. Codex가 주 검증 통합이며 다른 어댑터는 각 도구의 공개 상태 디렉터리 방식을 따릅니다. [MIT License](../LICENSE)로 배포됩니다.

