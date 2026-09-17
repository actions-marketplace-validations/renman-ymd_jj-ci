#!/usr/bin/env nu

# Every relative link in the markdown: the file it names exists, and when it
# carries an anchor, the target really has a heading that produces it.
#
# GitHub's anchor rule, near enough: lowercase, drop everything that is not a
# word character, a space or a hyphen, then spaces become hyphens.

const LINK = '\[[^\]]*\]\(([^)\s]+)\)'

def main []: nothing -> nothing {
  let files = (glob '**/*.md' --exclude ['**/.jj/**'])
  let problems = ($files | each { |f| check-file $f } | flatten)

  if ($problems | is-not-empty) {
    $problems | each { |p| print -e $p } | ignore
    print -e $"($problems | length) broken link\(s)"
    exit 1
  }
  print $"($files | length) markdown files, every link resolves"
}

def check-file [file: string]: nothing -> list<string> {
  let dir = ($file | path dirname)
  open --raw $file
  | strip-fences
  | parse --regex $LINK
  | get capture0
  | where { |l| not (($l | str starts-with 'http') or ($l | str starts-with 'mailto:')) }
  | each { |link| verify $file $dir $link }
  | compact
}

def verify [file: string, dir: string, link: string]: nothing -> any {
  let parts = ($link | split row '#')
  let target = ($parts | get 0)
  let anchor = ($parts | get -o 1)
  let resolved = (if ($target | is-empty) { $file } else { $dir | path join $target })

  if not ($resolved | path exists) {
    return $"($file | path basename): ($link) — no such file"
  }
  if $anchor == null or not ($resolved | str ends-with '.md') {
    return null
  }
  if $anchor in (anchors $resolved) {
    null
  } else {
    $"($file | path basename): ($link) — no heading makes that anchor"
  }
}

def anchors [file: string]: nothing -> list<string> {
  open --raw $file
  | lines
  | where { |l| $l =~ '^#{1,6} ' }
  | each { |l|
    $l
    | str replace --regex '^#+\s+' ''
    | str lowercase
    | str replace --all --regex '[^\w\s-]' ''
    | str trim
    | str replace --all --regex '\s+' '-'
  }
}

# A fenced block can hold anything, including text that looks like a link.
def strip-fences []: string -> string {
  mut keep = []
  mut inside = false
  for line in ($in | lines) {
    if ($line | str starts-with '```') {
      $inside = (not $inside)
      continue
    }
    if not $inside { $keep = ($keep | append $line) }
  }
  $keep | str join "\n"
}
