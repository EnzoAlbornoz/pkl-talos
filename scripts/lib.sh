# Helpers shared by the mise tasks. Source it; don't run it.

# Talos version of the package in build/talos.
package_talos_version() {
  if [[ ! -f build/talos/version.pkl ]]; then
    echo "build/talos has no package; run 'mise run generate' first." >&2
    return 1
  fi
  pkl eval -x talos build/talos/version.pkl
}

# major.minor of a version: 1.14.4 -> 1.14.
minor_of() {
  local version="${1#v}"
  echo "${version%%-*}" | cut -d. -f1,2
}

# Whether version $1 <= version $2.
version_le() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]]
}

# A file: URI for path $1, which Pkl reads like any other resource.
file_uri() {
  local dir
  # On Windows (Git Bash), `pwd -W` gives C:/... paths, which pkl.exe understands.
  dir="$(cd "$(dirname "$1")" && { pwd -W 2>/dev/null || pwd; })"
  case "$dir" in
  /*) echo "file://$dir/$(basename "$1")" ;;
  *) echo "file:///$dir/$(basename "$1")" ;;
  esac
}
