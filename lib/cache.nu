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

export def prune [root: string, config_hash: string]: nothing -> nothing {
  let base = ($root | path join ".jj" "jj-ci" $LAYOUT)
  if not ($base | path exists) { return }
  ls $base
  | where type == dir
  | where { |e| ($e.name | path basename) != $config_hash }
  | each { |e| rm -rf $e.name }
  | ignore
}

# Keyed by working copy, not by commit: jj run reuses its copies.
export def bootstrap-marker [root: string, slot: string]: nothing -> string {
  let d = ($root | path join ".jj" "jj-ci" $LAYOUT "bootstrap")
  mkdir $d
  $d | path join ($slot | hash sha256 | str substring 0..15)
}

def safe [name: string]: nothing -> string {
  $name | str replace --all --regex '[^A-Za-z0-9._-]' "_"
}
