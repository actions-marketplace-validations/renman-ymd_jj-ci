use log.nu [warn]
use detect.nu

const CHECK_KEYS = [
  command stages scope input paths pass-files requires skip-if skip-reason enabled cache doc
  workspace
]
const FORMAT_KEYS = [command patterns enabled line-range-arg run-tool-if-zero-line-ranges]
const TOP_KEYS = [jj-ci filesets bootstrap format checks]

export def find [root: string]: nothing -> any {
  let candidates = [
    ($root | path join ".jj-ci.toml")
    ($root | path join ".jj-ci" "config.toml")
  ]
  $candidates | where { |p| $p | path exists } | get -o 0
}

export def load [root: string]: nothing -> record {
  let file = (find $root)
  if $file == null { error make { msg: "no .jj-ci.toml in this repository" } }

  let raw = (open --raw $file)
  let doc = (try { $raw | from toml } catch { |e|
    error make { msg: $"($file) is not valid TOML: ($e.msg)" }
  })

  reject-unknown ($doc | columns) $TOP_KEYS $file "top level"

  let meta = ($doc | get -o jj-ci | default {})
  let version = ($meta | get -o version | default 1)
  if $version > 1 {
    warn $"($file) declares version ($version); this jj-ci understands 1"
  }

  let checks = (normalize-checks ($doc | get -o checks | default {}) $file)
  let autodetect = ($meta | get -o autodetect | default false)

  let checks = (if ($checks | is-empty) and $autodetect {
    detect suggest $root
  } else {
    $checks
  })

  {
    path: $file
    hash: ($raw | hash sha256 | str substring 0..15)
    version: $version
    autodetect: $autodetect
    filesets: ($doc | get -o filesets | default {})
    bootstrap: (normalize-bootstrap ($doc | get -o bootstrap) $file)
    format: (normalize-format ($doc | get -o format | default {}) $file)
    checks: $checks
  }
}

def normalize-bootstrap [table: any, file: string]: nothing -> any {
  if $table == null { return null }
  {
    command: (expect-command ($table | get -o command) $file "bootstrap")
    fingerprint: ($table | get -o fingerprint | default [])
  }
}

def normalize-format [table: record, file: string]: nothing -> record {
  $table
  | columns
  | reduce --fold {} { |name, acc|
      let tool = ($table | get $name)
      reject-unknown ($tool | columns) $FORMAT_KEYS $file $"format.($name)"
      let patterns = ($tool | get -o patterns | default [])
      if ($patterns | is-empty) {
        error make { msg: $"($file): format.($name) has no patterns, so it would never run" }
      }
      $acc | insert $name {
        command: (expect-command ($tool | get -o command) $file $"format.($name)")
        patterns: $patterns
        enabled: ($tool | get -o enabled | default true)
        line-range-arg: ($tool | get -o line-range-arg)
        run-tool-if-zero-line-ranges: ($tool | get -o run-tool-if-zero-line-ranges)
      }
    }
}

def normalize-checks [table: record, file: string]: nothing -> table {
  $table
  | columns
  | each { |name|
      let c = ($table | get $name)
      reject-unknown ($c | columns) $CHECK_KEYS $file $"checks.($name)"

      let input = ($c | get -o input | default "files")
      if $input not-in ["files" "description"] {
        error make { msg: $"($file): checks.($name).input must be \"files\" or \"description\"" }
      }

      # A description belongs to one commit, so the tip alone is not enough.
      let scope = ($c | get -o scope | default (if $input == "description" { "each" } else { "tip" }))
      if $scope not-in ["tip" "each"] {
        error make { msg: $"($file): checks.($name).scope must be \"tip\" or \"each\"" }
      }

      let paths = ($c | get -o paths | default [])

      # Reading a description needs no checkout.
      let workspace = ($c | get -o workspace | default ($input == "description"))

      {
        name: $name
        command: (expect-command ($c | get -o command) $file $"checks.($name)")
        stages: ($c | get -o stages | default ["push"])
        scope: $scope
        input: $input
        workspace: $workspace
        paths: $paths
        pass-files: ($c | get -o pass-files | default true)
        requires: ($c | get -o requires | default [])
        skip-if: ($c | get -o skip-if | default [])
        skip-reason: ($c | get -o skip-reason | default "skip-if matched")
        enabled: ($c | get -o enabled | default true)
        cache: ($c | get -o cache | default true)
        doc: ($c | get -o doc | default "")
      }
    }
}

def expect-command [value: any, file: string, where: string]: nothing -> list<string> {
  if $value == null {
    error make { msg: $"($file): ($where) has no command" }
  }
  if ($value | describe | str starts-with "list") == false {
    error make { msg: $"($file): ($where).command must be a list of strings, e.g. [\"bun\", \"run\", \"test\"]" }
  }
  if ($value | is-empty) {
    error make { msg: $"($file): ($where).command is empty" }
  }
  $value | each { |a| $a | into string }
}

def reject-unknown [got: list<string>, known: list<string>, file: string, where: string] {
  let unknown = ($got | where { |k| $k not-in $known })
  if ($unknown | is-not-empty) {
    error make {
      msg: ($"($file): unknown key\(s) in ($where): ($unknown | str join ', ')"
        + $"\nknown keys: ($known | str join ', ')")
    }
  }
}
