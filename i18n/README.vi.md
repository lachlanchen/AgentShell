[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# AgentShell

*Các tài khoản AI CLI riêng biệt trong nhiều terminal, cùng dùng một cây làm việc thật.*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](../LICENSE)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](../docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)

AgentShell cho phép terminal cá nhân, phòng thí nghiệm và công ty dùng các tài khoản Codex khác nhau mà không sao chép dự án, đổi người dùng Unix hay duy trì container. Tiến trình vẫn ở thư mục hiện tại; các biến môi trường được nhà cung cấp hỗ trợ chỉ định tuyến xác thực và trạng thái vào hồ sơ có tên.

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## Khả năng chính

- Mỗi nhãn có xác thực Codex và trạng thái nhà cung cấp độc lập.
- Có thể chia sẻ chỉ mục phiên Codex nhưng vẫn tách biệt thông tin đăng nhập.
- Không sao chép không gian làm việc; Git, Conda, công cụ xây dựng và tệp giữ nguyên vị trí.
- Đối số gốc, mô hình, prompt, ảnh và tùy chọn CLI tương lai được chuyển tiếp đầy đủ.
- Giữ nguyên quy trình `codexr`, `/rename`, tìm kiếm đường dẫn một phần và `codexmv`.
- Codex được tích hợp đầy đủ; Claude Code, Gemini CLI và Copilot CLI có bộ điều hợp trạng thái.

## Bắt đầu nhanh

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

Để đăng nhập từ máy từ xa hoặc không có giao diện:

```bash
codex --account personal login --device-auth
```

Xem [hướng dẫn đầy đủ](../docs/tutorial.md) về cài đặt, đăng nhập trình duyệt, chuyển tài khoản, lịch sử riêng/chung, tiếp tục phiên, di chuyển và khắc phục sự cố.

## Sử dụng hằng ngày

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

Tùy chọn `--account` của AgentShell phải đứng đầu. Khi không có tùy chọn tài khoản, `codex`, `codexr` và `codexmv` vẫn hoạt động như trước.

## Xác thực riêng và lịch sử tùy chọn

| Chế độ | Xác thực | Chỉ mục SQLite tiếp tục | Trường hợp phù hợp |
|---|---|---|---|
| `private` | Riêng trong hồ sơ | Riêng trong hồ sơ | Công việc phòng thí nghiệm/công ty cần bảo mật |
| `shared` | Riêng trong hồ sơ | Chỉ mục cơ sở dùng chung | Tiếp tục cùng phiên từ nhiều tài khoản |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

AgentShell sử dụng ranh giới công khai của Codex giữa `CODEX_HOME` và `CODEX_SQLITE_HOME`. Công cụ không bao giờ chia sẻ thông tin đăng nhập chỉ để dùng chung danh mục tiếp tục phiên.

## Sơ đồ kho mã

| Đường dẫn | Mục đích |
|---|---|
| [bin/agentshell](../bin/agentshell) | Môi trường hồ sơ và bộ phân phối lệnh |
| [shell/agentshell.bash](../shell/agentshell.bash) | Tích hợp đối số tài khoản trong Bash |
| [install.sh](../install.sh) | Trình cài đặt người dùng có thể chạy lặp lại |
| [docs/tutorial.md](../docs/tutorial.md) | Hướng dẫn đầy đủ từ cài đặt đến xử lý lỗi |
| [docs/architecture.md](../docs/architecture.md) | Ranh giới trạng thái và thiết kế an toàn |
| [docs/providers.md](../docs/providers.md) | Bộ điều hợp cho các AI CLI |
| [tests/test.sh](../tests/test.sh) | Kiểm thử tích hợp cô lập |

## Xác minh

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

## Phạm vi bảo mật

Không commit thư mục hồ sơ, `auth.json`, token, cookie, cơ sở dữ liệu SQLite hoặc tệp môi trường riêng. Các hồ sơ dùng lịch sử chung có thể thấy tiêu đề, bản xem trước và đường dẫn trong chỉ mục. AgentShell dành cho cùng một người dùng Unix đáng tin cậy, không phải lớp cô lập bảo mật của hệ điều hành.

## Trích dẫn

Nếu dùng AgentShell trong nghiên cứu hoặc công cụ, hãy trích dẫn kho mã này. GitHub đọc [CITATION.cff](../CITATION.cff) và hiển thị bảng **Cite this repository**.

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## Trạng thái và giấy phép

AgentShell là tiện ích Bash ít phụ thuộc và được duy trì tích cực. Codex là tích hợp chính đã được xác minh; các bộ điều hợp khác tuân theo cơ chế thư mục trạng thái công khai của từng công cụ. Dự án dùng [giấy phép MIT](../LICENSE).

