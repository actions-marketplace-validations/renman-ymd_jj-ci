# Opt-in detection of an existing hook runner.
#
# Off unless the repo sets `jj-ci.autodetect = true` and declares no checks of
# its own: guessing is a convenience, never a surprise.
#
# Every runner below is built on git — it wants a repository, an index, or
# both. The isolated copy `jj run` produces is a plain directory with no .git,
# so a detected runner is marked `workspace = true` and runs against your real
# working copy. That is weaker than checking the revision being published, and
# `jj-ci doctor` says so; declaring checks explicitly is how you get the strong
# form.

const RUNNERS = [
  {
    name: "hk"
    marker: "hk.pkl"
    bin: "hk"
    command: [hk check --all]
    pass-files: false
  }
  {
    name: "lefthook"
    marker: "lefthook.yml"
    bin: "lefthook"
    command: [lefthook run pre-commit --all-files]
    pass-files: false
  }
  {
    name: "lefthook"
    marker: "lefthook.yaml"
    bin: "lefthook"
    command: [lefthook run pre-commit --all-files]
    pass-files: false
  }
  {
    name: "prek"
    marker: "prek.toml"
    bin: "prek"
    command: [prek run --files]
    pass-files: true
  }
  {
    name: "pre-commit"
    marker: ".pre-commit-config.yaml"
    bin: "pre-commit"
    command: [pre-commit run --files]
    pass-files: true
  }
]

# The first runner whose marker file exists, or null.
export def probe [root: string]: nothing -> any {
  $RUNNERS | where { |r| ($root | path join $r.marker) | path exists } | get -o 0
}

# A ready-to-run check list for that runner, in the normalized shape config.nu
# produces. `prek` shares pre-commit's config file, so it wins when installed.
export def suggest [root: string]: nothing -> table {
  let found = (probe $root)
  if $found == null { return [] }

  let bin = if $found.bin == "pre-commit" and (which prek | is-not-empty) { "prek" } else { $found.bin }
  let command = ($found.command | each { |a| if $a == $found.bin { $bin } else { $a } })

  [
    {
      name: $found.name
      command: $command
      stages: ["push"]
      scope: "tip"
      input: "files"
      workspace: true
      paths: []
      pass-files: $found.pass-files
      requires: [$bin]
      skip-if: []
      skip-reason: "skip-if matched"
      enabled: true
      cache: false
      doc: $"autodetected from ($found.marker)"
    }
  ]
}
