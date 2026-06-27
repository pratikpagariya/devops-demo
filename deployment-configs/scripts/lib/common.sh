#!/usr/bin/env bash
###############################################################################
# common.sh — shared helpers for the platform setup scripts.
###############################################################################

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# wait_for_secret <namespace> <name> [retries] [sleep_seconds]
wait_for_secret() {
  local ns="$1" name="$2" retries="${3:-60}" sleep_s="${4:-5}"
  log "Waiting for secret ${ns}/${name} ..."
  for ((i=1; i<=retries; i++)); do
    if kubectl -n "$ns" get secret "$name" >/dev/null 2>&1; then
      ok "Secret ${ns}/${name} present."
      return 0
    fi
    sleep "$sleep_s"
  done
  die "Timed out waiting for secret ${ns}/${name} (is External Secrets healthy? is the AWS secret populated?)"
}

# helm_install <release> <repo/chart> <version> <namespace> <values-file> [extra --set args...]
helm_install() {
  local release="$1" chart="$2" version="$3" namespace="$4" values="$5"; shift 5
  log "Installing ${release} (${chart}@${version}) → ns/${namespace}"
  helm upgrade --install "$release" "$chart" \
    --version "$version" \
    --namespace "$namespace" --create-namespace \
    -f "$values" \
    --wait --timeout 15m \
    "$@"
  ok "${release} installed."
}
