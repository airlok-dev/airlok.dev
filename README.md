# airlok.dev

The [airlok](https://github.com/airlok-dev/airlok) website, served by GitHub Pages from `main` at https://airlok.dev. Plain HTML and CSS: no framework, no build step, no scripts, no external fonts.

- `install.sh` is served at https://airlok.dev/install.sh. It asks the GitHub API for the latest airlok release, checks that release's `airlok-installer.sh` against the sha256 digest GitHub publishes for it, and runs it.
- `docs/index.html` mirrors the Configuration, AIRLOK.md, redaction, and Sessions sections of the airlok README. It is updated by hand when those sections change.

CI validates the HTML with html-validate, checks that no page loads scripts, fonts, or anything from another origin, and runs shellcheck on `install.sh`.
