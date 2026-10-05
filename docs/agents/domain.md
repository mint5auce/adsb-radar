# Domain docs

This repository uses a single-context domain documentation layout.

## Before exploring

Read `GLOSSARY.md` at the repository root and relevant ADRs in `docs/adr/`.
If these files do not exist, proceed silently.
The domain-modeling skill creates them when terms or decisions are resolved.

## File structure

- `GLOSSARY.md`: shared domain vocabulary.
- `docs/adr/`: numbered architecture decision records.

## Use the glossary's vocabulary

Use defined domain terms in issue titles, proposals, hypotheses, and tests.
When a needed concept is missing, reconsider the terminology or note the gap for domain-modeling.

## Flag ADR conflicts

Explicitly identify any existing ADR that a proposal contradicts and explain why reopening it is warranted.
