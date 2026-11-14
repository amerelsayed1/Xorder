#!/usr/bin/env bash
#
# sync-coordination.sh — keep the XOrder coordination docs identical in both repos.
#
# The three coordination files live in BOTH repos' docs/coordination/ (each repo must
# carry its own committed copy so the file travels with its history and CI). That
# duplication drifts unless it is mirrored. Each file has ONE owning side — this script
# mirrors each file FROM its owner TO the other repo, so an edit is only ever made in the
# owning repo and copied out, never clobbered in the wrong direction.
#
# Ownership (from the files' own headers):
#   POS_TO_BACKEND.md      owner: POS      -> source xorder-pos, dest xorder-cloud
#   BACKEND_TO_POS.md      owner: backend  -> source xorder-cloud, dest xorder-pos
#   BACKOFFICE_TO_CLOUD.md owner: cloud    -> source xorder-cloud, dest xorder-pos
#
# This copy is identical in both repos (xorder-cloud/scripts/ and xorder-pos/scripts/).
# It assumes the two repos are checked out as siblings under one parent folder, e.g.
# ~/Projects/Xorder/{xorder-cloud,xorder-pos}. If the sibling repo is not present it
# exits 0 with a note, so a single-repo clone or CI job is never broken by it.
#
# Usage (from either repo):
#   scripts/sync-coordination.sh          mirror each file from its owner to the other repo
#   scripts/sync-coordination.sh --check  report drift, exit non-zero if any (writes nothing)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WS_ROOT="$(cd "$REPO_ROOT/.." && pwd)"
NEW="$WS_ROOT/xorder-cloud/docs/coordination"
POS="$WS_ROOT/xorder-pos/docs/coordination"

if [[ ! -d "$WS_ROOT/xorder-cloud" || ! -d "$WS_ROOT/xorder-pos" ]]; then
  echo "sync-coordination: sibling repo not found next to $REPO_ROOT — nothing to sync." >&2
  echo "  expected both xorder-cloud/ and xorder-pos/ under $WS_ROOT" >&2
  exit 0
fi

# file:source_dir:dest_dir  (source is the owning repo)
MAP=(
  "POS_TO_BACKEND.md:$POS:$NEW"
  "BACKEND_TO_POS.md:$NEW:$POS"
  "BACKOFFICE_TO_CLOUD.md:$NEW:$POS"
)

check_only=false
[[ "${1:-}" == "--check" ]] && check_only=true

drift=0
for entry in "${MAP[@]}"; do
  file="${entry%%:*}"; rest="${entry#*:}"
  src="${rest%%:*}/$file"; dst="${rest#*:}/$file"

  if [[ ! -f "$src" ]]; then echo "MISSING source: $src" >&2; drift=1; continue; fi
  if [[ ! -f "$dst" ]]; then echo "MISSING dest:   $dst" >&2; drift=1; fi

  if cmp -s "$src" "$dst" 2>/dev/null; then
    $check_only && echo "ok      $file (in sync)"
  else
    drift=1
    if $check_only; then
      echo "DRIFT   $file  (owner copy: ${src#$WS_ROOT/})"
    else
      cp "$src" "$dst"
      echo "synced  $file  ${src#$WS_ROOT/} -> ${dst#$WS_ROOT/}"
    fi
  fi
done

if $check_only && [[ $drift -ne 0 ]]; then
  echo "" >&2
  echo "Coordination docs have drifted. Run scripts/sync-coordination.sh to mirror from owners." >&2
  exit 1
fi

$check_only && [[ $drift -eq 0 ]] && echo "All coordination docs are in sync."
exit 0
