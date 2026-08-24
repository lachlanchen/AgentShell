[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

<div dir="rtl">

# AgentShell

*حسابات مختلفة لأدوات الذكاء الاصطناعي في طرفيات منفصلة، مع شجرة عمل حقيقية مشتركة.*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](../LICENSE)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](../docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)

يتيح AgentShell للطرفيات الشخصية والمخبرية وطرفيات الشركة استخدام عمليات دخول مختلفة إلى Codex من دون نسخ المشاريع أو تغيير مستخدم Unix أو صيانة حاويات. تبقى العملية في المجلد الحالي، بينما توجه متغيرات البيئة التي يدعمها كل مزود المصادقة والحالة إلى ملف تعريف مسمى.

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## القدرات الأساسية

- مصادقة Codex وحالة المزود منفصلتان لكل تسمية.
- يمكن مشاركة فهرس جلسات Codex اختياريا مع بقاء بيانات الدخول منفصلة.
- لا توجد نسخ لمساحة العمل؛ تبقى Git وConda وأدوات البناء والملفات في أماكنها.
- تمرر الوسائط الأصلية والنماذج والتعليمات والصور وخيارات CLI المستقبلية كما هي.
- تبقى مسارات `codexr` و`/rename` والبحث الجزئي و`codexmv` متاحة.
- تكامل Codex كامل، مع محولات حالة لـ Claude Code وGemini CLI وCopilot CLI.

## بدء سريع

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

للدخول من جهاز بعيد أو بلا واجهة رسومية:

```bash
codex --account personal login --device-auth
```

راجع [الدليل الكامل](../docs/tutorial.md) للتثبيت، والدخول عبر المتصفح، وتبديل الحسابات، والسجل الخاص أو المشترك، واستئناف الجلسات، والترحيل، وحل المشكلات.

## الاستخدام اليومي

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

يجب أن يأتي خيار AgentShell المسمى `--account` أولا. من دونه، تحتفظ أوامر `codex` و`codexr` و`codexmv` بسلوكها المعتاد.

## بيانات دخول خاصة وسجل قابل للاختيار

| الوضع | بيانات الدخول | فهرس SQLite للاستئناف | الاستخدام المقترح |
|---|---|---|---|
| `private` | خاصة بالملف | خاص بالملف | عمل مخبري أو مؤسسي سري |
| `shared` | خاصة بالملف | فهرس أساسي مشترك | استئناف الجلسات نفسها من عدة حسابات |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

يستخدم AgentShell الفصل الموثق في Codex بين `CODEX_HOME` و`CODEX_SQLITE_HOME`. ولا يشارك بيانات الدخول لمجرد مشاركة دليل الاستئناف.

## خريطة المستودع

| المسار | الغرض |
|---|---|
| [bin/agentshell](../bin/agentshell) | بيئة تشغيل الملفات وموزع الأوامر |
| [shell/agentshell.bash](../shell/agentshell.bash) | دمج وسيطة الحساب في Bash |
| [install.sh](../install.sh) | مثبت قابل للتكرار للمستخدم الحالي |
| [docs/tutorial.md](../docs/tutorial.md) | دليل كامل من البداية إلى حل المشكلات |
| [docs/architecture.md](../docs/architecture.md) | حدود الحالة وتصميم الأمان |
| [docs/providers.md](../docs/providers.md) | محولات أدوات الذكاء الاصطناعي |
| [tests/test.sh](../tests/test.sh) | اختبارات تكامل معزولة |

## التحقق

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

## نطاق الأمان

لا ترفع مجلدات الملفات الشخصية أو `auth.json` أو الرموز أو ملفات الارتباط أو قواعد SQLite أو ملفات البيئة الخاصة. تستطيع الملفات التي تستخدم السجل المشترك رؤية العناوين والمعاينات والمسارات المفهرسة. AgentShell مخصص لمستخدم Unix واحد موثوق، وليس عزلا أمنيا على مستوى نظام التشغيل.

## الاستشهاد

إذا استخدمت AgentShell في البحث أو الأدوات، فاستشهد بهذا المستودع. يقرأ GitHub ملف [CITATION.cff](../CITATION.cff) ويعرض لوحة **Cite this repository**.

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## الحالة والترخيص

AgentShell أداة Bash خفيفة قليلة الاعتماديات وتخضع لصيانة مستمرة. Codex هو التكامل الرئيسي الذي جرى التحقق منه، وتتبع المحولات الأخرى آليات مجلدات الحالة المعلنة لأدواتها. يصدر المشروع وفق [رخصة MIT](../LICENSE).

</div>

