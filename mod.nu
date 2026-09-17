#!/usr/bin/env nu

# Reached through the bin/jj-ci symlink, a bare `path self` reports the
# symlink's own directory, and every `use` below would look for bin/lib.
const ROOT = (path self | path expand | path dirname)
const SELF = (path self | path expand)

use $"($ROOT)/commands"
use $"($ROOT)/lib/log.nu" [err]
use $"($ROOT)/lib/runner.nu"

def self-cmd []: nothing -> list<string> {
  [$nu.current-exe "--no-config-file" $SELF]
}

# Interactively, returning an exit code would print a stray `0`.
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
  --strict # a check that cannot run here fails instead of being skipped
]: nothing -> nothing {
  raise (
    commands ci invoke (self-cmd) $stage $revisions $here $fix $no_cache (
      $only | split row "," | where { |s| ($s | str trim) != "" }
    ) $verbose $jobs $strict
  ) "jj-ci: checks failed"
}

# Checks a stage would run here, without running any of them.
export def checks [
  stage: string = "push" # stage to list
  --json # one line of JSON, for a CI matrix
]: nothing -> any {
  let rows = (commands checks invoke $stage)
  if $json { $rows | to json --raw } else { $rows }
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

  (ansi cyan)jj-ci checks(ansi reset) [stage] [--json]          list a stage without running it
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

# Unexported on purpose: exporting them would put `jj-ci main ci` in the
# module's namespace, and a script dispatches `main <sub>` either way.

def "main ci" [
  --stage (-s): string = "push"
  --revisions (-r): string
  --here
  --fix
  --no-cache
  --only: string = ""
  --jobs (-j): int = 1
  --verbose
  --strict
]: nothing -> nothing {
  try {
    (ci --stage $stage --revisions $revisions --here=$here --fix=$fix
        --no-cache=$no_cache --only $only --jobs $jobs --verbose=$verbose
        --strict=$strict)
  } catch { exit 1 }
}

def "main checks" [stage: string = "push", --json]: nothing -> nothing {
  try { print (checks $stage --json=$json) } catch { |e| err $e.msg; exit 1 }
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

def "main __revision" []: nothing -> nothing {
  if ($env | get -o JJ_CI_PLAN) == null {
    err "__revision is run by jj-ci itself, inside jj run"
    exit 2
  }
  exit (runner revision)
}
