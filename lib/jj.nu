# Thin wrappers over the jj CLI.
#
# Reads pass --ignore-working-copy so they neither snapshot nor write an
# operation; call `snapshot` once up front instead. Every wrapper assumes the
# caller has already changed into the workspace root: jj prints paths relative
# to the current directory, and `glob:` filesets resolve against it too.

const HEX = '[0-9a-f]{8,64}'

export def root []: nothing -> string {
  let r = (^jj --ignore-working-copy root | complete)
  if $r.exit_code != 0 { error make { msg: "not inside a jj repository" } }
  $r.stdout | str trim
}

# Take the one snapshot the rest of the run relies on.
export def snapshot []: nothing -> nothing {
  ^jj util snapshot | complete | ignore
}

# Oldest first, which is the order jj run uses and the order in which a broken
# stack is most usefully reported.
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

# Paths a revset touches, optionally narrowed by filesets. jj does the
# intersection itself, so `paths` entries are just extra positional arguments
# and fileset aliases resolve for free.
export def changed-files [revset: string, filesets: list<string> = []]: nothing -> list<string> {
  let r = (
    ^jj --ignore-working-copy diff --no-pager -r $revset --name-only ...$filesets | complete
  )
  if $r.exit_code != 0 {
    error make { msg: $"jj diff failed for ($revset):\n($r.stderr | str trim)" }
  }
  $r.stdout | lines | where { |l| ($l | str trim) != "" }
}

# What `jj git push` would publish, asked of jj itself so that every flag
# combination is honoured. Verified not to need the network.
#
# jj 0.45 prints, on stdout:
#   Changes to push to origin:
#     bookmark: name [add to <commit>]
#     bookmark: name [move forward from <commit> to <commit>]
#     bookmark: name [delete from <commit>]
#
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
          # Built by concatenation: `(` opens an interpolation in $"…", so a
          # regex group cannot be written inline.
          let m = ($row.action | parse -r ('(?<commit>' + $HEX + ')\s*$'))
          # The dry run abbreviates; everything else here speaks in full commit
          # ids, and an abbreviation compared against a full id matches nothing
          # — silently, which would leave tip-scoped checks unrun on a gate
          # that still reported success.
          { bookmark: $row.bookmark, commit: (resolve ($m | get -o 0.commit | default "")) }
        }
      | where { |t| $t.commit != "" }
    )
    deletes: ($rows | where { |row| $row.action | str starts-with "delete" } | get bookmark)
    raw: ($text | str trim)
  }
}

# Expand an abbreviated commit id, or "" when jj cannot resolve it.
export def resolve [prefix: string]: nothing -> string {
  if ($prefix | is-empty) { return "" }
  let r = (
    ^jj --ignore-working-copy log --no-pager --no-graph -r $prefix -T 'commit_id' | complete
  )
  if $r.exit_code != 0 { "" } else { $r.stdout | str trim }
}

# Path of the repo-level config file. Since jj 0.44 this lives outside the
# repository (under the user's config directory), which is why a versioned
# .jj-ci.toml has to be rendered into it rather than the other way round.
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

# Move the nearest bookmark onto @-, the way the common `tug` alias does.
# Having no bookmark to move is not an error: `jj git push` will say so itself.
export def tug []: nothing -> nothing {
  ^jj bookmark move --from 'heads(::@- & bookmarks())' --to '@-' | complete | ignore
}

# Commit id of a bookmark, re-resolved after `jj fix` has rewritten history.
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
