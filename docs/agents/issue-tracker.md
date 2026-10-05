# Issue tracker: GitHub

Issues and specs live as GitHub issues.
Use the `gh` CLI for tracker operations.

## Repository selection

Infer the repository from `git remote -v` when a remote is configured.
If no remote identifies the repository, ask for its owner/name and pass `--repo owner/name` to `gh` commands.

## Conventions

- Create: `gh issue create --title "..." --body-file <path>`.
- Read: `gh issue view <number> --comments`; fetch labels when needed.
- List: `gh issue list --state open --json number,title,body,labels,comments`, with appropriate filters.
- Comment: `gh issue comment <number> --body-file <path>`.
- Apply labels: `gh issue edit <number> --add-label "..."`.
- Remove labels: `gh issue edit <number> --remove-label "..."`.
- Close: `gh issue close <number> --comment "..."`.

Write multiline bodies to a temporary file and pass it with `--body-file`.
Use the triage role mapping in `triage-labels.md`.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Skill operations

When a skill says "publish to the issue tracker", create a GitHub issue.
When a skill says "fetch the relevant ticket", run `gh issue view <number> --comments`.

## Wayfinding operations

- Map: one issue labelled `wayfinder:map`, containing Notes, Decisions-so-far, and Fog.
- Child tickets: link GitHub sub-issues to the map; if unavailable, use a task list in the map and `Part of #<map>` in each child.
- Types: use `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task`.
- Blocking: use native GitHub issue dependencies; if unavailable, record `Blocked by: #<number>` in the child body.
- Frontier: choose the first open, unassigned child in map order whose blockers are all closed.
- Claim: assign the ticket to the driving developer before work.
- Resolve: comment with the answer, close the ticket, then append a summary and link to the map's Decisions-so-far.
