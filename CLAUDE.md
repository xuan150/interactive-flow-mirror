# Interactive Flow Mirror

Unity 6000.3.15f1 (URP). Interactive mirror installation prototype. Main direction: the nameless world (無名之物), an autonomous particle world that changes irregularly on its own; viewers are never drawn, they only sense they are there from how the world reacts ([ADR 0002](docs/adr/0002-nameless-world-reads-presences-only.md)). A viewer is simulated with the mouse for now. The earlier figure and light-veil direction (sketches 01–09, `Scenes/Main.unity`) is parked; its look-dev and notice work live on the `archive/*` branches.

**Start every session from `docs/ROADMAP.md`**: architecture, decisions, and progress live there. Terms are in `GLOSSARY.md`, decisions in `docs/adr/`, each sketch's steps and chosen values in `docs/sketches/`.

Commits follow Conventional Commits, one concern per commit.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (xuan150/interactive-flow-mirror), via the `gh` CLI. See `docs/agents/issue-tracker.md` (local only, not in the repo).

### Domain docs

Single-context: `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md` (local only, not in the repo).
