# Output helpers.
#
# Verdict lines always say how the verdict was reached — ran, cached, or
# skipped and why. A run that prints nothing but green ticks must never hide
# the fact that nothing actually executed.

export def title [msg: string] { print $"(ansi cyan_bold)($msg)(ansi reset)" }
export def info [msg: string] { print $"  (ansi dark_gray)·(ansi reset) ($msg)" }
export def warn [msg: string] { print $"(ansi yellow)warning:(ansi reset) ($msg)" }
export def err [msg: string] { print -e $"(ansi red_bold)error:(ansi reset) ($msg)" }

# One line per (revision, check). `how` is the provenance: a duration, the word
# "cached", or a skip reason.
export def verdict [
  rev: string # short change id, or "" when the check is not revision-bound
  check: string
  status: string # pass | fail | skip
  how: string
]: nothing -> nothing {
  let mark = match $status {
    "pass" => $"(ansi green)✓(ansi reset)"
    "fail" => $"(ansi red)✗(ansi reset)"
    _ => $"(ansi dark_gray)‒(ansi reset)"
  }
  let detail = match $status {
    "skip" => $"(ansi dark_gray)($how)(ansi reset)"
    _ => $"(ansi dark_gray)($how)(ansi reset)"
  }
  print $"  (ansi yellow)($rev | fill -a l -w 8)(ansi reset)  ($check | fill -a l -w 16) ($mark)  ($detail)"
}

# Final summary. Returns the exit code the caller should use.
export def summary [results: list<record>]: nothing -> int {
  let failed = ($results | where status == "fail")
  let skipped = ($results | where status == "skip")
  let passed = ($results | where status == "pass")
  print ""
  if ($failed | is-empty) {
    let tail = if ($skipped | is-empty) { "" } else { $", ($skipped | length) skipped" }
    print $"(ansi green_bold)ok(ansi reset) — ($passed | length) passed($tail)"
    0
  } else {
    let names = ($failed | get check | uniq | str join ", ")
    print $"(ansi red_bold)failed(ansi reset) — ($names)"
    1
  }
}

export def plural [n: int, word: string]: nothing -> string {
  if $n == 1 { $"($n) ($word)" } else { $"($n) ($word)s" }
}
