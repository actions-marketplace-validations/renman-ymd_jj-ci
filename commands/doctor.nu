# `jj-ci doctor` — say what works here and what does not, before a push does.

const LIB = path self "../lib"
use $"($LIB)/log.nu" *
use $"($LIB)/jj.nu"
use $"($LIB)/config.nu"
use $"($LIB)/render.nu"
use $"($LIB)/detect.nu"

export def invoke [bin: string]: nothing -> int {
  title "environment"
  line "jj" (jj version)
  line "nushell" $"nu (version | get version)"
  line "jj-ci" $bin
  line "on PATH" (if (which jj-ci | is-not-empty) { "yes" } else { "no — aliases need the absolute path" })

  let ci_alias = (alias-of "ci")
  let push_alias = (alias-of "push")
  line "alias jj ci" $ci_alias
  line "alias jj push" $push_alias

  let root = (try { jj root } catch { null })
  if $root == null {
    print ""
    warn "not inside a jj repository — run this again from one to check its policy"
    return 0
  }

  print ""
  title "repository"
  line "root" $root
  line "colocated" (
    if (($root | path join ".git") | path exists) { "yes" } else {
      "no — a git-based hook runner (pre-commit, lefthook, hk) cannot run here"
    }
  )

  let file = (config find $root)
  if $file == null {
    line "policy" "none — `jj push` here behaves exactly like `jj git push`"
    let found = (detect probe $root)
    if $found != null {
      info $"($found.marker) is present; `jj-ci init --detect` would wire ($found.name) up"
    }
    return 0
  }

  let cfg = (try { config load $root } catch { |e|
    line "policy" $"($file) — (ansi red)invalid(ansi reset)"
    print ($e.msg)
    return 1
  })

  line "policy" $file
  line "checks" (
    $cfg.checks
    | group-by { |c| $c.stages | str join "+" }
    | transpose stage items
    | each { |r| $"($r.stage): ($r.items | get name | str join ', ')" }
    | str join "; "
  )
  line "formatters" (
    if ($cfg.format | columns | is-empty) { "none" } else { $cfg.format | columns | str join ", " }
  )
  line "bootstrap" (
    if $cfg.bootstrap == null { "none" } else { $cfg.bootstrap.command | str join " " }
  )

  cd $root
  let rendered = (try { render ensure $root $cfg; "in sync" } catch { |e| $e.msg })
  line "repo config" $rendered

  let missing = (
    $cfg.checks
    | each { |c| $c.requires | where { |b| which $b | is-empty } }
    | flatten
    | uniq
  )
  line "missing tools" (if ($missing | is-empty) { "none" } else { $missing | str join ", " })
  0
}

def alias-of [name: string]: nothing -> string {
  let r = (^jj config list $"aliases.($name)" | complete)
  if $r.exit_code != 0 or ($r.stdout | str trim | is-empty) {
    "not installed — run `jj-ci install`"
  } else {
    $r.stdout | str trim | str replace --regex '^[^=]*=\s*' ''
  }
}

def line [key: string, value: string] {
  print $"  ($key | fill -a l -w 14) ($value)"
}
