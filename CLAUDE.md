# CLAUDE.md

## Principles

1. **Back up in GitHub.** Make sure the project is in a GitHub repo and pushed. If it isn't, set that up first.

2. **Commit after every change.**

3. **Roadmap with phases.** For every update or coding task, design a roadmap with phases. Most phases should include tests so we don't break things as we go. A phase can also be research: when working with a new API or designing something new, run an isolated experiment inside the update's folder (outside the main code) to play around and see what works and what doesn't.

4. **Modular code.** Keep code modular so AI can always work in an isolated context and fix isolated things. UI especially must be highly isolated, standardized, built from reusable components, and minimalistic: only what we truly need.

5. **Be an orchestrator.** Use your own agents. For UX, always launch a UX expert to think through all the features, ideally several, one per part, so the UX is very well thought through.

## updates/ folder

Each update gets its own folder:

`updates/YYYY-MM-DD UPDATE_NAME - OPEN` (or `- CLOSED` when finished)

Inside:

- **`update vX.md`**: X is the version of the update, starting at 1. Contains the goal, the roadmap to achieve it, and status tracking: what was done, what decisions were made, and what's next.
- **`wiki.md`**: decisions and lessons that teach us what works and what doesn't in this update. Principles and lessons we've discovered.
- **Optional files** to log anything else related to the update, for example when we reopen it to finish or fix something.
