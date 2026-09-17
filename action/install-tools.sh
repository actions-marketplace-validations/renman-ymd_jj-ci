#!/usr/bin/env bash
# Put jj and nushell on PATH for the steps that follow.
#
# Release tarballs rather than a package manager or another action: both
# projects publish static builds for every runner platform, so this needs no
# toolchain, no cache warm-up and no third party.
set -euo pipefail

# jj run --ignore-changes and --passthrough, which the runner depends on.
JJ_MINIMUM=0.44.0

JJ_VERSION=${JJ_VERSION:-latest}
NU_VERSION=${NU_VERSION:-latest}
INSTALL_DIR=${INSTALL_DIR:-$RUNNER_TEMP/jj-ci-tools}

die() {
  printf '::error::%s\n' "$*" >&2
  exit 1
}

# Release assets for both projects are named by the Rust target triple.
target_triple() {
  local os arch
  os=$(uname -s)
  arch=$(uname -m)
  case "$os" in
    Linux)
      case "$arch" in
        x86_64 | amd64) printf 'x86_64-unknown-linux-musl' ;;
        aarch64 | arm64) printf 'aarch64-unknown-linux-musl' ;;
        *) die "unsupported CPU on this Linux runner: $arch" ;;
      esac
      ;;
    Darwin)
      case "$arch" in
        x86_64) printf 'x86_64-apple-darwin' ;;
        arm64) printf 'aarch64-apple-darwin' ;;
        *) die "unsupported CPU on this macOS runner: $arch" ;;
      esac
      ;;
    *)
      die "jj-ci runs on Linux and macOS runners; this one reports '$os'. bin/jj-ci is a symlink and the checks are nushell, neither of which survives a Windows runner intact."
      ;;
  esac
}

fetch() {
  local url=$1 dest=$2
  curl --fail --silent --show-error --location \
    --retry 3 --retry-delay 2 --output "$dest" "$url"
}

# The asset names carry the version, so the /releases/latest/download/ redirect
# cannot be used and the tag has to be read first.
latest_tag() {
  local repo=$1 url body
  url="https://api.github.com/repos/$repo/releases/latest"
  if [ -n "${GH_TOKEN:-}" ]; then
    body=$(curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
      --header "Authorization: Bearer $GH_TOKEN" "$url")
  else
    body=$(curl --fail --silent --show-error --location --retry 3 --retry-delay 2 "$url")
  fi
  printf '%s' "$body" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n 1
}

# Both projects tag as x.y.z, jj with a leading v and nushell without; the
# inputs accept either spelling.
resolve_version() {
  local repo=$1 want=$2 tag
  if [ "$want" = latest ]; then
    tag=$(latest_tag "$repo") || die "could not read the latest release of $repo"
    [ -n "$tag" ] || die "could not read the latest release of $repo"
  else
    tag=$want
  fi
  printf '%s' "${tag#v}"
}

install_jj() {
  local version=$1 triple=$2 tmp
  tmp=$(mktemp -d)
  fetch "https://github.com/jj-vcs/jj/releases/download/v${version}/jj-v${version}-${triple}.tar.gz" \
    "$tmp/jj.tar.gz" || die "no jj $version build for $triple"
  tar -xzf "$tmp/jj.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/jj" "$INSTALL_DIR/jj"
  rm -rf "$tmp"
}

install_nu() {
  local version=$1 triple=$2 tmp
  tmp=$(mktemp -d)
  fetch "https://github.com/nushell/nushell/releases/download/${version}/nu-${version}-${triple}.tar.gz" \
    "$tmp/nu.tar.gz" || die "no nushell $version build for $triple"
  tar -xzf "$tmp/nu.tar.gz" -C "$tmp"
  # The nushell tarball unpacks into one directory named after the target.
  install -m 0755 "$tmp"/nu-*/nu "$INSTALL_DIR/nu"
  rm -rf "$tmp"
}

# True when $1 is older than $2.
older_than() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" = "$1" ] &&
    [ "$1" != "$2" ]
}

main() {
  local triple jj_version nu_version
  triple=$(target_triple)
  mkdir -p "$INSTALL_DIR"

  if [ "$JJ_VERSION" = preinstalled ]; then
    command -v jj >/dev/null || die "jj-version is 'preinstalled' but jj is not on PATH"
  else
    jj_version=$(resolve_version jj-vcs/jj "$JJ_VERSION")
    install_jj "$jj_version" "$triple"
  fi

  if [ "$NU_VERSION" = preinstalled ]; then
    command -v nu >/dev/null || die "nu-version is 'preinstalled' but nu is not on PATH"
  else
    nu_version=$(resolve_version nushell/nushell "$NU_VERSION")
    install_nu "$nu_version" "$triple"
  fi

  printf '%s\n' "$INSTALL_DIR" >>"$GITHUB_PATH"
  export PATH="$INSTALL_DIR:$PATH"

  local have
  have=$(jj --version | awk '{ print $2 }')
  if older_than "$have" "$JJ_MINIMUM"; then
    die "jj $have is older than the $JJ_MINIMUM jj-ci needs (jj run --ignore-changes, --passthrough)"
  fi

  printf 'jj  %s\n' "$have"
  printf 'nu  %s\n' "$(nu --version)"
}

main "$@"
