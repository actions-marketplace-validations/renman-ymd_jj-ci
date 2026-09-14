# Remembering green results.
#
# A commit id is content-addressed, so "this commit passed this check" stays
# true for as long as the check itself is unchanged — which is why the config
# hash is part of the path. Entries are empty marker files rather than one
# shared index, so parallel jobs never race over a write.
#
# What the cache cannot see: an upgraded formatter, a lockfile outside the
# bootstrap fingerprint, a check that reads the network. Those are what
# `--no-cache` and `cache = false` are for.

const LAYOUT = "v1"

export def dir [root: string, config_hash: string]: nothing -> string {
  $root | path join ".jj" "jj-ci" $LAYOUT $config_hash
}

export def hit [cache_dir: string, commit: string, check: string]: nothing -> bool {
  ($cache_dir | path join $commit (safe $check)) | path exists
}

export def store [cache_dir: string, commit: string, check: string]: nothing -> nothing {
  let d = ($cache_dir | path join $commit)
  mkdir $d
  "" | save --force --raw ($d | path join (safe $check))
}

export def forget [cache_dir: string, commit: string, check: string]: nothing -> nothing {
  let f = ($cache_dir | path join $commit (safe $check))
  if ($f | path exists) { rm -f $f }
}

# Drop entries belonging to older versions of the config, so the cache does not
# grow a directory per edit.
export def prune [root: string, config_hash: string]: nothing -> nothing {
  let base = ($root | path join ".jj" "jj-ci" $LAYOUT)
  if not ($base | path exists) { return }
  ls $base
  | where type == dir
  | where { |e| ($e.name | path basename) != $config_hash }
  | each { |e| rm -rf $e.name }
  | ignore
}

# Bootstrap state is per working copy, not per commit: `jj run` reuses its
# copies, so the marker records which fingerprint that directory was last
# prepared for.
export def bootstrap-marker [root: string, slot: string]: nothing -> string {
  let d = ($root | path join ".jj" "jj-ci" $LAYOUT "bootstrap")
  mkdir $d
  $d | path join ($slot | hash sha256 | str substring 0..15)
}

def safe [name: string]: nothing -> string {
  $name | str replace --all --regex '[^A-Za-z0-9._-]' "_"
}
