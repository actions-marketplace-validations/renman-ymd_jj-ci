const LIB = path self "../lib"

use $"($LIB)/log.nu" *
use $"($LIB)/jj.nu"
use $"($LIB)/config.nu"
use $"($LIB)/render.nu"
use $"($LIB)/runner.nu"

export def invoke [
  self_cmd: list<string>
  stage: string
  revisions: any # revset, or null for the default
  here: bool
  fix: bool
  no_cache: bool
  only: list<string>
  verbose: bool
  jobs: int
]: nothing -> int {
  let root = (jj root)
  cd $root
  jj snapshot

  let file = (config find $root)
  if $file == null {
    err $"no .jj-ci.toml in ($root) — run `jj-ci init` to create one"
    return 1
  }
  let cfg = (config load $root)
  render ensure $root $cfg

  let revset = (
    if $here { "@" } else if $revisions != null { $revisions } else { (default-revset) }
  )

  # Before resolving revisions: jj fix rewrites the commits it touches.
  if $fix and ($cfg.format | columns | is-not-empty) {
    title "jj fix"
    if not (jj fix $revset) { return 1 }
  }

  let revs = (jj revisions $revset)
  if ($revs | is-empty) {
    warn $"no revisions in ($revset)"
    return 0
  }

  let tips = (if $here { [($revs | last | get commit)] } else {
    jj revisions $"heads\(($revset))" | get commit
  })

  title $"($stage): ((plural ($revs | length) 'revision')) in ($revset)"
  runner execute $root $cfg $stage $revs $tips $revset $self_cmd {
    no_cache: $no_cache, only: $only, verbose: $verbose, here: $here, jobs: $jobs
  }
}

# Unpushed work. With the usual immutable_heads() that includes remote
# bookmarks, this is the same set `jj fix` and `jj run` default to, so `jj ci`
# and plain jj commands talk about the same commits.
def default-revset []: nothing -> string {
  "reachable(@, mutable())"
}
