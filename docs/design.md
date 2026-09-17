# Why jj-ci is shaped like this

Background for the decisions behind [jj-ci](../README.md): why the gate sits at
`jj push` rather than at commit time, what the runner actually does to your
repository, and the things it refuses to do.

## Why there is no pre-commit hook

jj has no hooks, and a pre-commit hook would not fit it if it did. A commit
exists the moment a file is saved, `jj describe` and `jj squash` rewrite
commits afterwards, and intermediate commits are allowed to be broken — that
freedom is the point of the tool. Hooking "commit" would mean checking
something you did not ask to be final, constantly.

The moment that does correspond to a git pre-commit hook is **publication**:
the point where the work becomes other people's problem. So the gate is `jj
push`, and it checks exactly what `jj git push` is about to send.

This is the same conclusion reached by the jj maintainers (discussion #403),
the `jj-hooks` and `jj-pre-push` projects, and aazuspan's write-up. jj-ci
differs from those three in one respect: it builds on `jj run` (jj 0.43+)
instead of git worktrees, so it needs no colocated git repository.

## How it runs things

**Materialisation.** Anything that needs files is handed to one `jj run
--ignore-changes`, which checks each revision out into a private copy under
`.jj/run/` and runs the command there. Your working copy is never touched and
never has to be clean, and no colocated git repository is needed.

**What the copy does not have.** Only tracked files: no `node_modules`, no
`target/`, no `.venv`. The copies *are reused between invocations*, so
`[bootstrap]` is paid once per fingerprint change rather than once per check.
Tools that insist on a git repository (pre-commit, lefthook, hk) cannot run
there at all; give those checks `workspace = true` and accept that they then
describe your working copy rather than the revision being published.

**What is not materialised.** Description checks read `jj log`, and stage
membership, `requires`, `skip-if`, path matching and the cache are all settled
in the real working copy first. A revision with nothing left to do is never
checked out.

**Failure.** Every check of a revision runs, so one pass tells you everything
that is wrong with it. Revisions are visited oldest first and the run stops at
the first one that fails, which lands you on the commit that broke the stack
rather than on every commit after it.

**Output.** One line per verdict, always saying how it was reached:

```
  qvzowpvq  typecheck        ✓  4.1s
  qvzowpvq  fmt              ✓  cached
  qvzowpvq  itest            ‒  no docker daemon
  —         pre-commit       ‒  not on PATH: pre-commit
```

A check's own output is shown only when it fails; `--verbose` streams it
instead. `--jobs N` checks N revisions in parallel, at the cost of output
arriving in batches at the end (jj streams a subprocess only when running one
job at a time).

**Cache.** A commit id is content-addressed, so "this commit passed this check"
stays true while the check is unchanged — the cache key includes a hash of
`.jj-ci.toml`. Entries are marker files under `.jj/jj-ci/`. What the cache
cannot see: an upgraded tool, or a lockfile outside your bootstrap fingerprint.
That is what `--no-cache` and `cache = false` are for.

## What this deliberately does not do

- **No pre-commit hook.** See above. `jj ci --here` is the closest thing, and
  you ask for it.
- **No rewriting behind your back.** The gate reports; `--fix` is how you ask
  for `jj fix`. Formatting rewrites the target revisions *and their
  descendants*, so a push that silently changed the commits it was about to
  publish would be a surprise, even an undoable one.
- **No ecosystem knowledge.** `requires` is a uniform `which`; it does not know
  that "docker" means a live daemon. Write that as `skip-if`.
- **No runner autodetection unless asked.** `jj-ci.autodetect = true`, or
  `jj-ci init --detect` to write the stanza out where you can edit it.
- **No reading checks out of a GitHub workflow.** The detectable runners —
  pre-commit, lefthook, hk, prek — are declarative command lists with stable
  schemas. A workflow is a program: matrices to expand, setup steps to
  discard, a step whose whole body is `sudo unshare --net`. Guessing there
  would produce checks that silently run the wrong thing, and the gate has to
  work before anything reaches GitHub anyway. The arrow points the other way:
  the workflow reads the TOML.

## Prior art

- [`jj run`](https://docs.jj-vcs.dev/latest/design/run/) — the primitive this
  is built on; landed in jj 0.43.
- [jj-hooks](https://github.com/mattwilkinsonn/jj-hooks) — ephemeral git
  worktrees plus pre-commit/lefthook/hk, for colocated repositories.
- [jj-pre-push](https://github.com/acarapetis/jj-pre-push) — pre-commit before
  `jj git push`, colocated only.
- [Automating pre-push checks with jujutsu](https://www.aazuspan.dev/blog/automating-pre-push-checks-with-jujutsu/)
  — the `jj util exec` alias approach, and the reasoning for why pre-push is
  the right moment.
- [jj discussion #403](https://github.com/jj-vcs/jj/discussions/403) — the
  maintainers on why git hooks do not map onto jj, and what native hooks might
  look like.
