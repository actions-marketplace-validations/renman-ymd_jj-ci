# Running one check.
#
# Output is captured and shown only when the check fails: a passing gate should
# be a column of ticks, not a wall of tool chatter. `--verbose` streams instead,
# for the check that takes two minutes and you want to watch.

export def run-one [
  argv: list<string>
  cwd: string
  stdin: any # string for input = "description", otherwise null
  verbose: bool
]: nothing -> record {
  let started = (date now)
  cd $cwd

  let result = (if $verbose {
    # No pipe and no `complete`: either would capture the very output the user
    # asked to watch. try/catch is how the exit status is observed instead.
    let code = (try {
      if $stdin == null {
        ^($argv | first) ...($argv | skip 1)
      } else {
        $stdin | ^($argv | first) ...($argv | skip 1)
      }
      0
    } catch { 1 })
    { exit_code: $code, out: "" }
  } else {
    let r = (if $stdin == null {
      ^($argv | first) ...($argv | skip 1) | complete
    } else {
      $stdin | ^($argv | first) ...($argv | skip 1) | complete
    })
    { exit_code: $r.exit_code, out: (($r.stdout + $r.stderr) | str trim) }
  })

  {
    status: (if $result.exit_code == 0 { "pass" } else { "fail" })
    seconds: (((date now) - $started) / 1sec)
    output: $result.out
  }
}

export def argv-for [check: record, files: list<string>]: nothing -> list<string> {
  if ($check.input == "description") or (not $check.pass-files) or ($files | is-empty) {
    return $check.command
  }
  # `$files` anywhere in the command means "put them here"; otherwise they go
  # on the end, the way lint-staged and pre-commit --files do it.
  if ("$files" in $check.command) {
    $check.command | each { |a| if $a == "$files" { $files } else { [$a] } } | flatten
  } else {
    $check.command | append $files
  }
}

export def fmt-duration [seconds: float]: nothing -> string {
  if $seconds < 10 {
    $"($seconds | math round --precision 1)s"
  } else {
    $"($seconds | math round)s"
  }
}
