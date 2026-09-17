# `jj-ci completions nushell` — teach nushell about the two jj aliases.
#
# Nushell sees `jj` as one external binary, so `jj ci --<TAB>` completes
# nothing and `jj ci --help` prints jj's help rather than ours. An `extern`
# declaration for the two-word command fixes both: completion for the flags,
# and `help jj ci` rendering a real page.
#
# jj generates its own completions with `jj util completion nushell`, which
# overwrites one file and cannot know about aliases — hence a second file.

const LIB = path self "../lib"
use $"($LIB)/log.nu" [err, info]

# Returns the module rather than printing it, so that as a nushell command it
# can be piped: `jj-ci completions nushell | save ~/.config/nushell/…`. Run as a
# script, nushell prints the return value, so a shell redirect still works.
export def invoke [shell: string, ci_alias: string, push_alias: string]: nothing -> string {
  if $shell not-in ["nushell" "nu"] {
    info "the flags are stable and documented in the README; other shells are a small script away"
    error make --unspanned { msg: $"no completions for ($shell) — jj-ci ships nushell only" }
  }
  (template)
  | str replace --all "@CI@" $ci_alias
  | str replace --all "@PUSH@" $push_alias
}

# A def rather than a const: nushell resolves consts in source order, and this
# one is more readable at the bottom of the file than at the top.
def template []: nothing -> string {
  'module jj_ci_completions {

  def "nu-complete jj-ci stage" [] { [push ci] }

  # Run a stage of repo checks over a revset
  export extern "jj @CI@" [
    --stage(-s): string@"nu-complete jj-ci stage" # stage to run (default: push)
    --revisions(-r): string   # revset to check (default: reachable(@, mutable()))
    --here                    # check the working copy instead of isolated checkouts
    --fix                     # run jj fix over the same revisions first
    --no-cache                # ignore remembered green results
    --only: string            # run only these checks (comma-separated)
    --jobs(-j): int           # revisions to check in parallel (output is captured above 1)
    --verbose                 # stream each check output instead of showing it on failure
    --help(-h)                # print help
  ]

  # Run the push stage, then jj git push
  export extern "jj @PUSH@" [
    --bookmark(-b): string    # bookmark to push
    --change(-c): string      # push the bookmark of this change
    --revision(-r): string    # push the bookmarks of these revisions
    --named: string           # NAME=REVISION
    --remote: string          # remote to push to
    --all                     # push all bookmarks
    --tracked                 # push tracked bookmarks
    --deleted                 # push deleted bookmarks
    --allow-empty-description
    --dry-run                 # ask jj what would be pushed, run no checks
    --no-verify               # publish without running any check
    --no-tug                  # do not move the nearest bookmark onto the last described commit
    --fix                     # run jj fix before checking
    --no-cache                # ignore remembered green results
    --stage: string@"nu-complete jj-ci stage" # stage to run (default: push)
    --only: string            # run only these checks (comma-separated, repeatable)
    --jobs: int               # revisions to check in parallel
    --verbose                 # stream each check output
    --help(-h)                # print help
  ]

  # jj-ci: local checks for jj repositories
  export extern "jj-ci" [
    --help(-h)
  ]

  # Create a .jj-ci.toml in this repository
  export extern "jj-ci init" [
    --detect                  # start from a detected hook runner
    --force                   # overwrite an existing file
    --help(-h)
  ]

  # Print the jj aliases to add to your user config
  export extern "jj-ci install" [
    --format: string          # toml | nix | both
    --on-path                 # emit the bare name instead of an absolute path
    --write                   # write them with jj config set --user
    --help(-h)
  ]

  # Report what jj-ci can and cannot do here
  export extern "jj-ci doctor" [ --help(-h) ]

  # Print shell completions
  export extern "jj-ci completions" [ --help(-h) ]
}

export use jj_ci_completions *'
}
