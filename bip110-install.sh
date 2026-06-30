#!/usr/bin/env bash
#
# bip110-install.sh — switch a FutureBit Apollo onto the BIP-110 fork
# and select the "Bitcoin Knots 29.3 +BIP-110 (UASF)" node client.
#
#   Fork:   https://github.com/cmyk/apolloapi-v2  +  https://github.com/cmyk/apolloui-v2
#   Client: knots-bip110  (Bitcoin Knots v29.3.knots20260210+bip110-v0.4.1)
#
# Usage (run on the Apollo, as root):
#   sudo bash bip110-install.sh            # repoint to fork, update, enable BIP-110
#   sudo bash bip110-install.sh --revert   # repoint to upstream FutureBit, back to core
#   sudo DRY_RUN=1 bash bip110-install.sh  # show what it WOULD do, change nothing
#   sudo bash bip110-install.sh --yes      # skip the confirmation prompt
#
# ⚠️  BIP-110 is a contested UASF soft fork. Signalling now is harmless, but at the
#     mandatory-signalling flag day (~Aug 7 2026, block 961,632) an enforcing node will
#     reject the majority chain if support is low — and follow a minority/stalled chain.
#     This is opt-in. You can revert any time with --revert.

set -euo pipefail

APOLLO_DIR="${APOLLO_DIR:-/opt/apolloapi}"
UI_DIR="${UI_DIR:-$APOLLO_DIR/apolloui-v2}"

FORK_API="https://github.com/cmyk/apolloapi-v2.git"
FORK_UI="https://github.com/cmyk/apolloui-v2.git"
UPSTREAM_API="https://github.com/jstefanop/apolloapi-v2.git"
UPSTREAM_UI="https://github.com/jstefanop/apolloui-v2.git"

CLIENT="knots-bip110"
REVERT_CLIENT="core-28.1"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
REVERT=0

Y='\033[1;33m'; R='\033[0;31m'; G='\033[0;32m'; N='\033[0m'
info() { echo -e "${Y} ---> $*${N}"; }
ok()   { echo -e "${G} ---> $*${N}"; }
err()  { echo -e "${R}Error: $*${N}" >&2; }

for arg in "$@"; do
  case "$arg" in
    --revert) REVERT=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) err "unknown option: $arg"; exit 1 ;;
  esac
done

run() {
  echo -e "${G}\$ $*${N}"
  [ "$DRY_RUN" = "1" ] && return 0
  "$@"
}

# --- preconditions ---
if [ "$DRY_RUN" != "1" ] && [ "$(id -u)" -ne 0 ]; then
  err "must run as root (use sudo)"; exit 1
fi
if [ ! -d "$APOLLO_DIR/.git" ] || [ ! -d "$UI_DIR/.git" ]; then
  err "this does not look like an Apollo ($APOLLO_DIR or $UI_DIR is not a git repo)"; exit 1
fi

# --- confirmation ---
if [ "$ASSUME_YES" != "1" ] && [ "$DRY_RUN" != "1" ]; then
  echo
  if [ "$REVERT" = "1" ]; then
    echo -e "${Y}This will repoint your Apollo back to upstream FutureBit and switch the node"
    echo -e "client back to ${REVERT_CLIENT}.${N}"
  else
    echo -e "${R}This will repoint your Apollo to the community BIP-110 fork, update it, and"
    echo -e "enable the BIP-110 (UASF) node client. BIP-110 is contested — read the warning"
    echo -e "at the top of this script. You can undo with: sudo bash $0 --revert${N}"
  fi
  read -r -p "Type 'yes' to continue: " reply
  [ "$reply" = "yes" ] || { err "aborted"; exit 1; }
fi

# --- record current state for easy revert ---
PREV_FILE="$APOLLO_DIR/.bip110-prev-remotes"
if [ "$REVERT" != "1" ] && [ "$DRY_RUN" != "1" ]; then
  {
    echo "api_origin=$(git -C "$APOLLO_DIR" remote get-url origin 2>/dev/null || echo unknown)"
    echo "ui_origin=$(git -C "$UI_DIR" remote get-url origin 2>/dev/null || echo unknown)"
  } > "$PREV_FILE" 2>/dev/null || true
  info "saved current remotes to $PREV_FILE"
fi

# --- repoint remotes ---
if [ "$REVERT" = "1" ]; then
  info "repointing remotes to upstream FutureBit"
  run git -C "$APOLLO_DIR" remote set-url origin "$UPSTREAM_API"
  run git -C "$UI_DIR"     remote set-url origin "$UPSTREAM_UI"
  TARGET_CLIENT="$REVERT_CLIENT"
else
  info "repointing remotes to the BIP-110 fork"
  run git -C "$APOLLO_DIR" remote set-url origin "$FORK_API"
  run git -C "$UI_DIR"     remote set-url origin "$FORK_UI"
  TARGET_CLIENT="$CLIENT"
fi

# --- run the Apollo's own update (git reset --hard + pull + yarn + restart) ---
info "running the Apollo updater against the new remotes"
if [ -x "$APOLLO_DIR/backend/update" ] || [ "$DRY_RUN" = "1" ]; then
  run bash "$APOLLO_DIR/backend/update"
else
  err "$APOLLO_DIR/backend/update not found — is this a supported Apollo OS version?"; exit 1
fi

# --- select the node client (installs the binary + updates the DB) ---
SWITCH="$APOLLO_DIR/backend/switch_bitcoin_software.sh"
if [ -x "$SWITCH" ]; then
  info "selecting node client: $TARGET_CLIENT"
  run bash "$SWITCH" "$TARGET_CLIENT"
elif [ "$DRY_RUN" = "1" ]; then
  info "selecting node client: $TARGET_CLIENT"
  info "(note: $SWITCH is not present on this OS yet; the update step above installs it on 2.1.x)"
  run bash "$SWITCH" "$TARGET_CLIENT"
else
  err "switch_bitcoin_software.sh not found — your Apollo OS may predate the client selector (needs 2.1.x)."
  err "The update above should have upgraded it; re-run this script, or pick the client in Settings -> Node."
  exit 1
fi

# --- restart the node service ---
info "restarting node service"
run systemctl restart node.service || true

# --- verify ---
if [ "$DRY_RUN" = "1" ]; then
  ok "dry-run complete — nothing was changed."
  exit 0
fi
CLI="$APOLLO_DIR/backend/node/bitcoin-cli"
DATADIR=$(grep -oE '\-datadir=[^ ]+' "$APOLLO_DIR/backend/node/node_start.sh" 2>/dev/null | head -1 | cut -d= -f2)
DATADIR="${DATADIR:-/media/nvme/Bitcoin}"
CONF="$APOLLO_DIR/backend/node/bitcoin.conf"
info "verifying node user-agent (may take a moment to come up)..."
for i in $(seq 1 30); do
  SUB=$("$CLI" -datadir="$DATADIR" -conf="$CONF" getnetworkinfo 2>/dev/null | grep -o '"subversion":[^,]*' || true)
  [ -n "$SUB" ] && break
  sleep 2
done
echo
if echo "${SUB:-}" | grep -qi "bip110"; then
  ok "BIP-110 node is live: $SUB"
  ok "Done. To undo later:  sudo bash $0 --revert"
elif [ "$REVERT" = "1" ]; then
  ok "Reverted to upstream FutureBit ($REVERT_CLIENT). Subversion: ${SUB:-<node still starting>}"
else
  err "Could not confirm BIP-110 in the user-agent yet (node may still be starting)."
  err "Check manually: $CLI -datadir=$DATADIR -conf=$CONF getnetworkinfo | grep subversion"
fi
