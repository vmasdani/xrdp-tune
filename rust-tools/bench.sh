#!/bin/bash
# Benchmark GNU grep/find/cat against ripgrep/fd/bat on a directory tree.
# Run: ./bench.sh <dir> [runs] [pattern] [extension]
# Each command runs once to warm the page cache, then [runs] times (default 5).
# Prints median and min wall time in ms, plus the output line count, which shows how
# much each tool searched: rg and fd skip .gitignore'd, hidden and binary files by default,
# while -uuu / -uu make them cover the same files as grep and find.
set -uo pipefail

DIR=${1:?usage: bench.sh <dir> [runs] [pattern] [extension]}
RUNS=${2:-5}
PAT=${3:-TODO}
EXT=${4:-ts}
cd "$DIR" || exit 1

for t in grep find rg fd bat; do
  command -v "$t" >/dev/null || { echo "$t not installed" >&2; exit 1; }
done

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

bench() {
  local label=$1 cmd=$2 i t0 times=() lines
  lines=$(bash -c "$cmd" 2>/dev/null | wc -l)
  for ((i = 0; i < RUNS; i++)); do
    t0=$(now_ms)
    bash -c "$cmd" >/dev/null 2>&1
    times+=($(( $(now_ms) - t0 )))
  done
  mapfile -t times < <(printf '%s\n' "${times[@]}" | sort -n)
  printf '%-44s %8s %8s %10s\n' "$label" "${times[$((RUNS / 2))]}" "${times[0]}" "$lines"
}

header() {
  echo
  echo "== $1"
  printf '%-44s %8s %8s %10s\n' command median_ms min_ms lines
}

echo "dir=$DIR runs=$RUNS pattern=$PAT ext=$EXT cpus=$(nproc) LANG=${LANG:-unset}"

header "literal search: $PAT"
bench "grep -rn" "grep -rn '$PAT' ."
bench "grep -rn --exclude-dir=node_modules,.git" "grep -rn --exclude-dir=node_modules --exclude-dir=.git '$PAT' ."
bench "rg -n (default, ignore-aware)" "rg -n '$PAT'"
bench "rg -n -uuu (same files as grep)" "rg -n -uuu '$PAT'"

header "case-insensitive regex: error|warn"
bench "grep -rniE" "grep -rniE 'error|warn' ."
bench "rg -ni (default)" "rg -ni 'error|warn'"
bench "rg -ni -uuu" "rg -ni -uuu 'error|warn'"

header "find by extension: *.$EXT"
bench "find -name" "find . -name '*.$EXT'"
bench "find -name, prune node_modules,.git" "find . \\( -name node_modules -o -name .git \\) -prune -o -name '*.$EXT' -print"
bench "fd -e (default, ignore-aware)" "fd -e '$EXT'"
bench "fd -uu -e (same files as find)" "fd -uu -e '$EXT'"

header "list every file"
bench "find -type f" "find . -type f"
bench "fd -uu -t f" "fd -uu -t f"

BIG=$(fd -uu -t f -e json -e yaml -e js -e ts -S +1m . 2>/dev/null | head -1)
if [ -n "$BIG" ]; then
  header "print one big file: $BIG ($(du -h "$BIG" | cut -f1))"
  bench "cat" "cat '$BIG'"
  bench "bat -pp (plain)" "bat -pp '$BIG'"
  bench "bat --color=always (highlighted)" "bat --color=always '$BIG'"
fi
