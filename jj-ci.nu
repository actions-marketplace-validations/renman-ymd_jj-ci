#!/usr/bin/env nu
# jj-ci — local checks for jujutsu repositories.
#
# jj has no hooks, and a pre-commit hook would not fit it anyway: a commit
# exists the moment a file is saved, and intermediate commits are allowed to be
# broken. The moment that corresponds to a git pre-commit hook is publication,
# so that is where the checks are: `jj push` gates `jj git push`.
#
# What gets checked is declared per repository in a versioned .jj-ci.toml.
# This program knows nothing about any language or tool.

const HERE = path self .
const SELF = path self "jj-ci.nu"

use commands/ci.nu
use commands/push.nu
use commands/init.nu
use commands/install.nu
use commands/completions.nu
use commands/doctor.nu
use lib/runner.nu
use lib/log.nu [err]

# The argv that re-invokes this program inside `jj run`. --no-config-file
# because a user's nushell config is for their shell, not for a check runner.
def self-cmd []: nothing -> list<string> {
  [$nu.current-exe "--no-config-file" $SELF]
}

def main []: nothing -> nothing {
  print $"jj-ci — local checks for jj repositories

  (ansi cyan)jj ci(ansi reset) [--stage S] [-r REVSET] [--here] [--fix]    run a stage
  (ansi cyan)jj push(ansi reset) [jj git push args…] [--no-verify]        gate, then publish

  (ansi cyan)jj-ci init(ansi reset) [--detect]                 write a .jj-ci.toml here
  (ansi cyan)jj-ci install(ansi reset) [--format nix|toml]     the two jj aliases to add
  (ansi cyan)jj-ci completions(ansi reset) nushell             completions for those aliases
  (ansi cyan)jj-ci doctor(ansi reset)                          what works here, what does not

Add --help to any of them. Policy lives in .jj-ci.toml, at the repository root."
}

# Run a stage of this repository's checks over a revset.
def "main ci" [
  --stage (-s): string = "push" # stage to run: push, ci, or any name the repo invents
  --revisions (-r): string # revset to check (default: reachable(@, mutable()))
  --here # check the working copy as it is, instead of isolated checkouts
  --fix # run jj fix over the same revisions first
  --no-cache # ignore remembered green results
  --only: string = "" # run only these checks (comma-separated)
  --jobs (-j): int = 1 # revisions to check in parallel; above 1, output is captured
  --verbose # stream each check's output instead of showing it only on failure
]: nothing -> nothing {
  let only = ($only | split row "," | where { |s| ($s | str trim) != "" })
  exit (
    ci invoke (self-cmd) $stage $revisions $here $fix $no_cache $only $verbose $jobs
  )
}

# Run the push stage over what would be published, then `jj git push`.
def --wrapped "main push" [...rest: string]: nothing -> nothing {
  if ("--help" in $rest) or ("-h" in $rest) {
    print $"jj push [jj git push arguments…]

Runs the push stage over exactly what `jj git push` would publish, then
publishes it. Unknown arguments go to jj untouched.

  --no-verify     publish without running anything
  --no-tug        do not move the nearest bookmark onto @-
  --fix           run jj fix over the published range first
  --stage S       run a stage other than push
  --only NAME     run only this check \(repeatable)
  --no-cache      ignore remembered green results
  --jobs N        check N revisions in parallel
  --verbose       stream each check's output
  --dry-run       forwarded to jj; asks what would be pushed and runs nothing"
    return
  }
  exit (push invoke (self-cmd) $rest)
}

# Write a starting .jj-ci.toml in this repository.
def "main init" [
  --detect # start from a hook runner already configured here
  --force # overwrite an existing file
]: nothing -> nothing {
  exit (init invoke $detect $force)
}

# Print the jj aliases to add to your user config.
def "main install" [
  --format: string = "both" # toml, nix, or both
  --on-path # emit the bare name, for when jj-ci is on PATH
  --write # write them with `jj config set --user` instead of printing
]: nothing -> nothing {
  exit (install invoke ($HERE | path join "bin" "jj-ci") $format $on_path $write)
}

# Print shell completions. Nushell only — see --help.
def "main completions" [
  shell: string = "nushell" # nushell
  --ci-alias: string = "ci" # name you gave the ci alias
  --push-alias: string = "push" # name you gave the push alias
]: nothing -> nothing {
  exit (completions invoke $shell $ci_alias $push_alias)
}

# Report what jj-ci can and cannot do in this repository.
def "main doctor" []: nothing -> nothing {
  exit (doctor invoke ($HERE | path join "bin" "jj-ci"))
}

# Internal: the per-revision runner `jj run` invokes inside an isolated copy.
def "main __revision" []: nothing -> nothing {
  if ($env | get -o JJ_CI_PLAN) == null {
    err "__revision is run by jj-ci itself, inside jj run"
    exit 2
  }
  exit (runner revision)
}
