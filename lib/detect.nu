# Every runner here is built on git, and the copy jj run produces has no .git,
# so they are marked `workspace = true` and see your working copy instead of
# the revision being published.

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

export def probe [root: string]: nothing -> any {
  $RUNNERS | where { |r| ($root | path join $r.marker) | path exists } | get -o 0
}

# `prek` shares pre-commit's config file, so it wins when installed.
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
