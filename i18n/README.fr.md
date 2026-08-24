[English](../README.md) · [العربية](README.ar.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Tiếng Việt](README.vi.md) · [中文 (简体)](README.zh-Hans.md) · [中文（繁體）](README.zh-Hant.md) · [Deutsch](README.de.md) · [Русский](README.ru.md)

[![LazyingArt banner](https://github.com/lachlanchen/lachlanchen/raw/main/figs/banner.png)](https://github.com/lachlanchen/lachlanchen/blob/main/figs/banner.png)

# AgentShell

*Des comptes d'IA distincts dans plusieurs terminaux, avec un seul véritable arbre de travail partagé.*

[![Test](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml/badge.svg)](https://github.com/lachlanchen/AgentShell/actions/workflows/test.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-22c55e.svg)](../LICENSE)
[![Documentation](https://img.shields.io/badge/docs-complete%20tutorial-2563eb)](../docs/tutorial.md)
[![LazyingArt](https://img.shields.io/badge/home-lazying.art-0EA5E9)](https://lazying.art)

AgentShell permet aux terminaux personnel, laboratoire et entreprise d'utiliser des connexions Codex différentes sans copier les projets, changer d'utilisateur Unix ni maintenir des conteneurs. Chaque processus reste dans le répertoire courant et les variables d'environnement prises en charge par les fournisseurs dirigent l'authentification et l'état vers un profil nommé.

| Donate | PayPal | Stripe |
| --- | --- | --- |
| [![Donate](https://img.shields.io/badge/Donate-LazyingArt-0EA5E9?style=for-the-badge&logo=kofi&logoColor=white)](https://chat.lazying.art/donate) | [![PayPal](https://img.shields.io/badge/PayPal-RongzhouChen-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/RongzhouChen) | [![Stripe](https://img.shields.io/badge/Stripe-Donate-635BFF?style=for-the-badge&logo=stripe&logoColor=white)](https://buy.stripe.com/aFadR8gIaflgfQV6T4fw400) |

## Capacités principales

- Authentification Codex et état du fournisseur indépendants pour chaque étiquette.
- Historique partagé facultatif sans mélanger les identifiants.
- Aucune copie de l'espace de travail : Git, Conda, outils de compilation et fichiers restent en place.
- Les arguments natifs, modèles, invites, images et futures options CLI sont transmis.
- Les flux `codexr`, `/rename`, recherche partielle de chemin et `codexmv` restent disponibles.
- Codex est entièrement intégré ; Claude Code, Gemini CLI et Copilot CLI disposent d'adaptateurs d'état.

## Démarrage rapide

```bash
git clone https://github.com/lachlanchen/AgentShell.git
cd AgentShell
./install.sh
. "$HOME/.bashrc"

agent-profile create personal
codex --account personal login
codex --account personal
```

Pour une connexion distante ou sans interface graphique :

```bash
codex --account personal login --device-auth
```

Consultez le [tutoriel complet](../docs/tutorial.md) pour l'installation, la connexion, le changement de compte, l'historique privé/partagé, la reprise, la migration et le dépannage.

## Utilisation quotidienne

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

L'option AgentShell `--account` doit être placée en premier. Sans cette option, `codex`, `codexr` et `codexmv` conservent leur comportement habituel.

## Identifiants privés et historique sélectionnable

| Mode | Identifiants | Index SQLite de reprise | Usage recommandé |
|---|---|---|---|
| `private` | Propres au profil | Propre au profil | Séparation confidentielle laboratoire/entreprise |
| `shared` | Propres au profil | Index de base partagé | Reprendre les mêmes sessions avec plusieurs comptes |

```bash
agent-profile history personal shared
agent-profile history company private
agentshell status personal
```

AgentShell utilise la séparation publique de Codex entre `CODEX_HOME` et `CODEX_SQLITE_HOME`. Il ne partage jamais les identifiants simplement pour partager le catalogue de reprise.

## Carte du dépôt

| Chemin | Rôle |
|---|---|
| [bin/agentshell](../bin/agentshell) | Moteur de profils et répartiteur de commandes |
| [shell/agentshell.bash](../shell/agentshell.bash) | Intégration des arguments de compte dans Bash |
| [install.sh](../install.sh) | Installateur utilisateur idempotent |
| [docs/tutorial.md](../docs/tutorial.md) | Tutoriel complet de bout en bout |
| [docs/architecture.md](../docs/architecture.md) | Frontières d'état et conception de sécurité |
| [docs/providers.md](../docs/providers.md) | Adaptateurs des différentes CLI d'IA |
| [tests/test.sh](../tests/test.sh) | Tests d'intégration isolés |

## Validation

```bash
bash -n bin/agentshell shell/agentshell.bash install.sh tests/test.sh
bash tests/test.sh
git diff --check
```

## Portée de sécurité

Ne validez jamais les répertoires de profils, `auth.json`, jetons, cookies, bases SQLite ou fichiers d'environnement privés. Les profils utilisant l'historique partagé voient les titres, aperçus et chemins indexés. AgentShell vise un même utilisateur Unix de confiance ; ce n'est pas une isolation de sécurité du système d'exploitation.

## Citation

Si vous utilisez AgentShell dans des travaux de recherche ou des outils, citez ce dépôt. GitHub lit [CITATION.cff](../CITATION.cff) et affiche le panneau **Cite this repository**.

```bibtex
@software{chen_agentshell_2026,
  author = {Chen, Lachlan},
  title = {AgentShell: Named AI CLI Account Profiles for Shared Working Trees},
  year = {2026},
  url = {https://github.com/lachlanchen/AgentShell}
}
```

## État et licence

AgentShell est un utilitaire Bash léger et activement maintenu. Codex est l'intégration principale validée ; les autres adaptateurs suivent les mécanismes publics de répertoire d'état. Le projet est distribué sous [licence MIT](../LICENSE).

