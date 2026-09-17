export def run-one [
  argv: list<string>
  cwd: string
  stdin: any # string for input = "description", otherwise null
  verbose: bool
]: nothing -> record {
  let started = (date now)
  cd $cwd

  let result = (if $verbose {
    # `complete` would capture the output --verbose exists to stream.
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
