# Every wrapper assumes the caller has changed into the workspace root: jj
# prints paths relative to the current directory, and `glob:` filesets resolve
# against it.

use log.nu [warn]

const HEX = '[0-9a-f]{8,64}'

# Most recent commit at or under @ with a description. @ is included because
# nothing guarantees it sits above the work; undescribed, it drops out anyway.
const TUG_TARGET = 'heads(::@ & ~description(exact:""))'

export def root []: nothing -> string {
  let r = (^jj --ignore-working-copy root | complete)
  if $r.exit_code != 0 { error make { msg: "not inside a jj repository" } }
  $r.stdout | str trim
}

export def snapshot []: nothing -> nothing {
  ^jj util snapshot | complete | ignore
}

export def revisions [revset: string]: nothing -> table {
  let r = (
    ^jj --ignore-working-copy log --no-pager --no-graph --reversed -r $revset
        -T 'commit_id ++ "\t" ++ change_id.short(8) ++ "\t" ++ description.first_line() ++ "\n"'
    | complete
  )
  if $r.exit_code != 0 {
    error make { msg: $"jj rejected the revset ($revset):\n($r.stderr | str trim)" }
  }
  $r.stdout
  | lines
  | where { |l| ($l | str trim) != "" }
  | each { |l|
      let f = ($l | split row "\t")
      { commit: ($f | get 0), change: ($f | get 1), desc: ($f | get 2? | default "") }
    }
}

export def description [commit: string]: nothing -> string {
  ^jj --ignore-working-copy log --no-pager --no-graph -r $commit -T 'description'
}

export def changed-files [revset: string, filesets: list<string> = []]: nothing -> list<string> {
  let r = (
    ^jj --ignore-working-copy diff --no-pager -r $revset --name-only ...$filesets | complete
  )
  if $r.exit_code != 0 {
    error make { msg: $"jj diff failed for ($revset):\n($r.stderr | str trim)" }
  }
  $r.stdout | lines | where { |l| ($l | str trim) != "" }
}

# A deletion publishes no code, so it carries no target to check.
export def push-targets [args: list<string>]: nothing -> record {
  let r = (^jj git push --dry-run ...$args | complete)
  let text = ($r.stdout + "\n" + $r.stderr)
  let rows = (
    $text
    | lines
    | parse -r '^\s*bookmark:\s+(?<bookmark>\S+)\s+\[(?<action>.*)\]\s*$'
  )
  {
    ok: ($r.exit_code == 0)
    parsed: (($rows | length) > 0 or ($text =~ 'Nothing changed|No bookmarks'))
    targets: (
      $rows
      | where { |row| not ($row.action | str starts-with "delete") }
      | each { |row|
          # Concatenated because `(` opens an interpolation in $"…".
          let m = ($row.action | parse -r ('(?<commit>' + $HEX + ')\s*$'))
          # The dry run abbreviates; an abbreviation compared against a full id
          # matches nothing, silently.
          { bookmark: $row.bookmark, commit: (resolve ($m | get -o 0.commit | default "")) }
        }
      | where { |t| $t.commit != "" }
    )
    deletes: ($rows | where { |row| $row.action | str starts-with "delete" } | get bookmark)
    raw: ($text | str trim)
  }
}

export def resolve [prefix: string]: nothing -> string {
  if ($prefix | is-empty) { return "" }
  let r = (
    ^jj --ignore-working-copy log --no-pager --no-graph -r $prefix -T 'commit_id' | complete
  )
  if $r.exit_code != 0 { "" } else { $r.stdout | str trim }
}

export def repo-config-path []: nothing -> string {
  let r = (^jj --ignore-working-copy config path --repo | complete)
  if $r.exit_code != 0 {
    error make { msg: $"could not locate the repo config:\n($r.stderr | str trim)" }
  }
  $r.stdout | str trim
}

export def fix [revset: string]: nothing -> bool {
  let r = (^jj fix -s $revset | complete)
  print ($r.stdout + $r.stderr | str trim)
  $r.exit_code == 0
}

# Not onto @-, which is often an undescribed commit jj git push then refuses to
# publish. Having no bookmark to move is not an error.
export def tug []: nothing -> nothing {
  let targets = (revisions $TUG_TARGET)

  # Under a merge, picking either side would publish a branch nobody named.
  if ($targets | length) > 1 {
    warn ("bookmark not moved: several described commits sit under @ — "
      + ($targets | each { |t| $t.change } | str join ", ")
      + "\n  move it yourself, or push with --no-tug")
    return
  }
  if ($targets | is-empty) { return }

  (^jj bookmark move --from 'heads(::@- & bookmarks())' --to ($targets | first | get commit)
   | complete | ignore)
}

export def bookmark-commit [name: string]: nothing -> string {
  let revset = ('bookmarks(exact:"' + $name + '")')
  let r = (
    ^jj --ignore-working-copy log --no-pager --no-graph -r $revset -T 'commit_id' | complete
  )
  if $r.exit_code != 0 { "" } else { $r.stdout | str trim }
}

export def version []: nothing -> string {
  ^jj --version | str trim
}
