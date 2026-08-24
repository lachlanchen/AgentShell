[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# AgentShell

*Cuentas de IA distintas en terminales separadas, compartiendo el mismo árbol de trabajo real.*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](../LICENSE)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](../docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)

AgentShell permite que las terminales personal, de laboratorio y de empresa usen inicios de sesión de Codex diferentes sin copiar proyectos, cambiar de usuario Unix ni mantener contenedores. Cada proceso permanece en el directorio actual, mientras las variables de entorno admitidas por cada proveedor dirigen la autenticación y el estado a un perfil con nombre.

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## Capacidades principales

- Autenticación de Codex y estado del proveedor independientes para cada etiqueta.
- Historial compartido opcional sin mezclar las credenciales.
- Ninguna copia del espacio de trabajo: Git, Conda, herramientas y archivos permanecen en su sitio.
- Los argumentos nativos, modelos, prompts, imágenes y futuras opciones de CLI se conservan.
- Continúan disponibles `codexr`, `/rename`, la búsqueda parcial de rutas y `codexmv`.
- Codex está plenamente integrado; Claude Code, Gemini CLI y Copilot CLI disponen de adaptadores de estado.

## Inicio rápido

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

Para iniciar sesión desde una máquina remota o sin interfaz gráfica:

```bash
codex --account personal login --device-auth
```

Consulta el [tutorial completo](../docs/tutorial.md) para instalación, inicio de sesión, cambio de cuenta, historial privado/compartido, reanudación, migración y solución de problemas.

## Uso cotidiano

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

La opción `--account` de AgentShell debe aparecer primero. Sin ella, `codex`, `codexr` y `codexmv` conservan su comportamiento habitual.

## Credenciales privadas e historial seleccionable

| Modo | Credenciales | Índice SQLite | Uso recomendado |
|---|---|---|---|
| `private` | Locales al perfil | Local al perfil | Separación confidencial de laboratorio o empresa |
| `shared` | Locales al perfil | Índice base compartido | Reanudar las mismas sesiones desde varias cuentas |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

AgentShell utiliza la separación pública de Codex entre `CODEX_HOME` y `CODEX_SQLITE_HOME`. Nunca comparte credenciales solo para compartir el catálogo de reanudación.

## Mapa del repositorio

| Ruta | Función |
|---|---|
| [bin/agentshell](../bin/agentshell) | Entorno de perfiles y distribuidor de comandos |
| [shell/agentshell.bash](../shell/agentshell.bash) | Integración de argumentos de cuenta en Bash |
| [install.sh](../install.sh) | Instalador idempotente para el usuario actual |
| [docs/tutorial.md](../docs/tutorial.md) | Tutorial completo de principio a fin |
| [docs/architecture.md](../docs/architecture.md) | Límites de estado y diseño de seguridad |
| [docs/providers.md](../docs/providers.md) | Adaptadores de las distintas CLI de IA |
| [tests/test.sh](../tests/test.sh) | Pruebas de integración aisladas |

## Validación

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

## Alcance de seguridad

No confirmes hogares de perfil, `auth.json`, tokens, cookies, bases SQLite ni archivos de entorno privados. Los perfiles con historial compartido pueden ver títulos, vistas previas y rutas del índice. AgentShell está diseñado para un mismo usuario Unix de confianza; no proporciona aislamiento de seguridad del sistema operativo.

## Cita

Si utilizas AgentShell en investigación o herramientas, cita este repositorio. GitHub lee [CITATION.cff](../CITATION.cff) y muestra el panel **Cite this repository**.

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## Estado y licencia

AgentShell es una utilidad Bash ligera y mantenida activamente. Codex es la integración principal verificada; los demás adaptadores siguen los controles públicos de directorios de estado. Se distribuye bajo la [licencia MIT](../LICENSE).

