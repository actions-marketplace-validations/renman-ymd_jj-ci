#!/usr/bin/env nu

# jj-ci — local checks for jujutsu repositories.
#
# jj has no hooks, and a pre-commit hook would not fit it: a commit exists the
# moment a file is saved, and intermediate commits are allowed to be broken.
# The moment that corresponds to a git pre-commit hook is publication, so that
# is where the checks are: `jj push` gates `jj git push`.
#
# What gets checked is declared per repository in a versioned .jj-ci.toml.
# This program knows nothing about any language or tool.
#
# Two entry points, one file:
#
#   use ~/Scripts/jj-ci      a nushell module — `jj-ci ci`, `jj-ci push`, …
#                            with native help and completions
#   bin/jj-ci                a symlink to this file, which jj's aliases run as
#                            a script — `jj ci`, `jj push`
#
# The exported commands serve the module and signal failure by raising; the
# unexported `main …` subcommands serve the script and turn that into an exit
# code. `main` subcommands do not need to be exported to work as a script, and
# leaving them unexported keeps `jj-ci main ci` out of the module's namespace.
#
# ROOT is expanded rather than taken as-is: reached through bin/jj-ci, a bare
# `path self` reports the symlink's own directory, and every `use` below would
# look for bin/lib and bin/commands. `path expand` resolves the link.

const ROOT = (path self | path expand | path dirname)
const SELF = (path self | path expand)

use $"($ROOT)/commands"
use $"($ROOT)/lib/log.nu" [err]
use $"($ROOT)/lib/runner.nu"

# The argv that re-invokes this file inside `jj run`, once per revision.
# --no-config-file is not a guardrail against your config: it avoids loading an
# interactive shell's furniture — completions, prompt, directory hooks — inside
# a checkout, N times per run.
def self-cmd []: nothing -> list<string> {
  [$nu.current-exe "--no-config-file" $SELF]
}

# Exit codes are the script's currency, not the shell's. Interactively a
# command that returned 0 would print a stray `0`, so the module raises instead
# and `main` turns the raise back into an exit code. --unspanned keeps it to one
# line rather than pointing at a line of jj-ci nobody needs to read.
def raise [code: int, msg: string]: nothing -> nothing {
  if $code != 0 { error make --unspanned { msg: $msg } }
}

# Run a stage of this repository's checks over a revset.
export def ci [
  --stage (-s): string = "push" # stage to run: push, ci, or any name the repo invents
  --revisions (-r): string # revset to check (default: reachable(@, mutable()))
  --here # check the working copy as it is, instead of isolated checkouts
  --fix # run jj fix over the same revisions first
  --no-cache # ignore remembered green results
  --only: string = "" # run only these checks (comma-separated)
  --jobs (-j): int = 1 # revisions to check in parallel; above 1, output is captured
  --verbose # stream each check's output instead of showing it only on failure
]: nothing -> nothing {
  raise (
    commands ci invoke (self-cmd) $stage $revisions $here $fix $no_cache (
      $only | split row "," | where { |s| ($s | str trim) != "" }
    ) $verbose $jobs
  ) "jj-ci: checks failed"
}

# Run the push stage over what would be published, then `jj git push`.
export def --wrapped push [...rest: string]: nothing -> nothing {
  if ("--help" in $rest) or ("-h" in $rest) {
    print (push-help)
    return
  }
  raise (commands push invoke (self-cmd) $rest) "jj-ci: push aborted"
}

# Write a starting .jj-ci.toml in this repository.
export def init [
  --detect # start from a hook runner already configured here
  --force # overwrite an existing file
]: nothing -> nothing {
  raise (commands init invoke $detect $force) "jj-ci: nothing written"
}

# Print the jj aliases to add to your user config.
export def install [
  --format: string = "both" # toml, nix, or both
  --on-path # emit the bare name, for when jj-ci is on PATH
  --write # write them with `jj config set --user` instead of printing
]: nothing -> nothing {
  raise (
    commands install invoke ($ROOT | path join "bin" "jj-ci") $format $on_path $write
  ) "jj-ci: aliases not installed"
}

# Shell completions for the jj aliases. Nushell only — see --help.
# Returned, not printed, so it can be piped straight into a file.
export def completions [
  shell: string = "nushell" # nushell
  --ci-alias: string = "ci" # name you gave the ci alias
  --push-alias: string = "push" # name you gave the push alias
]: nothing -> string {
  commands completions invoke $shell $ci_alias $push_alias
}

# Report what jj-ci can and cannot do in this repository.
export def doctor []: nothing -> nothing {
  raise (commands doctor invoke ($ROOT | path join "bin" "jj-ci")) "jj-ci: this repository has a problem"
}

export def main []: nothing -> nothing {
  print $"jj-ci — local checks for jj repositories

  (ansi cyan)jj ci(ansi reset) [--stage S] [-r REVSET] [--here] [--fix]    run a stage
  (ansi cyan)jj push(ansi reset) [jj git push args…] [--no-verify]        gate, then publish

  (ansi cyan)jj-ci init(ansi reset) [--detect]                 write a .jj-ci.toml here
  (ansi cyan)jj-ci install(ansi reset) [--format nix|toml]     the two jj aliases to add
  (ansi cyan)jj-ci completions(ansi reset) nushell             completions for those aliases
  (ansi cyan)jj-ci doctor(ansi reset)                          what works here, what does not

Add --help to any of them. Policy lives in .jj-ci.toml, at the repository root.
In nushell, `use ($ROOT)` gives the same commands with native help."
}

def push-help []: nothing -> string {
  $"jj push [jj git push arguments…]

Runs the push stage over exactly what `jj git push` would publish, then
publishes it. Unknown arguments go to jj untouched.

  --no-verify     publish without running anything
  --no-tug        do not move the nearest bookmark forward
  --fix           run jj fix over the published range first
  --stage S       run a stage other than push
  --only NAME     run only this check \(repeatable)
  --no-cache      ignore remembered green results
  --jobs N        check N revisions in parallel
  --verbose       stream each check's output
  --dry-run       forwarded to jj; asks what would be pushed and runs nothing"
}

# --- script entry points -----------------------------------------------------
#
# Unexported on purpose: `main <sub>` is how nushell dispatches a script's
# subcommands, and not exporting them keeps `jj-ci main ci` out of the module.

def "main ci" [
  --stage (-s): string = "push"
  --revisions (-r): string
  --here
  --fix
  --no-cache
  --only: string = ""
  --jobs (-j): int = 1
  --verbose
]: nothing -> nothing {
  try {
    (ci --stage $stage --revisions $revisions --here=$here --fix=$fix
        --no-cache=$no_cache --only $only --jobs $jobs --verbose=$verbose)
  } catch { exit 1 }
}

def --wrapped "main push" [...rest: string]: nothing -> nothing {
  try { push ...$rest } catch { exit 1 }
}

def "main init" [--detect, --force]: nothing -> nothing {
  try { init --detect=$detect --force=$force } catch { exit 1 }
}

def "main install" [
  --format: string = "both"
  --on-path
  --write
]: nothing -> nothing {
  try { install --format $format --on-path=$on_path --write=$write } catch { exit 1 }
}

def "main completions" [
  shell: string = "nushell"
  --ci-alias: string = "ci"
  --push-alias: string = "push"
]: nothing -> nothing {
  try { completions $shell --ci-alias $ci_alias --push-alias $push_alias } catch { exit 1 }
}

def "main doctor" []: nothing -> nothing {
  try { doctor } catch { exit 1 }
}

# Internal: the per-revision runner `jj run` invokes inside an isolated copy.
def "main __revision" []: nothing -> nothing {
  if ($env | get -o JJ_CI_PLAN) == null {
    err "__revision is run by jj-ci itself, inside jj run"
    exit 2
  }
  exit (runner revision)
}
