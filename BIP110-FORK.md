# FutureBit Apollo — BIP-110 (UASF) client option

This is a community fork of [`jstefanop/apolloapi-v2`](https://github.com/jstefanop/apolloapi-v2)
that adds **Bitcoin Knots 29.3 + BIP-110** as a selectable node client in the Apollo UI,
for Apollo owners who want to run and **signal** the BIP-110 ("Reduced Data" / UASF) soft fork
on their own node. Upstream FutureBit (reasonably) does not ship a contested consensus change as
a default — this fork makes it a deliberate **opt-in**.

Companion frontend fork: `apolloui-v2` (adds the dropdown entry).

## What it adds
- A new node client `knots-bip110` (UI label: *"Bitcoin Knots 29.3 +BIP-110 (UASF)"*),
  selectable under **Settings → Node**, alongside the stock Core/Knots options.
- The bundled binaries live in `backend/node/bin/knots-bip110/{aarch64,x86_64}/`.

## Binary provenance (verify before trusting)
Binaries are the official release from [`dathonohm/bitcoin`](https://github.com/dathonohm/bitcoin),
tag `v29.3.knots20260210+bip110-v0.4.1`:

| arch | tarball SHA256 |
|------|----------------|
| aarch64-linux-gnu | `6ec0c35f57e761e8434e62af1ac3eb1330e5a7c669c092d90c368c24e207c62d` |
| x86_64-linux-gnu  | `63db215f7b6860a44da8ab1aff29788178069feb24ac7b8296ee49236d16b295` |

The release `SHA256SUMS.asc` carries a **good GPG signature from Luke Dashjr's codesigning key**
(`1A3E 761F 19D2 CC77 85C5 502E A291 A2C4 5D0C 504A`). Always re-verify the upstream tarball
against these sums yourself before running consensus software.

## How to use
1. Repoint your Apollo's repos at this fork and run **Update** from the GUI
   (or `git remote set-url origin <this-fork>` in `/opt/apolloapi` and `/opt/apolloapi/apolloui-v2`).
2. In the web UI: **Settings → Node → Bitcoin Software → "Bitcoin Knots 29.3 +BIP-110 (UASF)"**, save.
3. The node restarts on the BIP-110 build. Confirm with:
   `bitcoin-cli getnetworkinfo | grep subversion` → should contain `UASF-BIP110`.

## ⚠️ Read this before enabling
BIP-110 is a **contested** soft fork with low support. Running it has real risk:
- A **mandatory-signaling flag day (~Aug 7 2026, block 961,632)**. If most hashrate is not
  signalling by then, a BIP-110-enforcing node will **reject the majority chain and follow a
  minority/stalled chain** — which also affects anything reading from your node (Electrum servers,
  explorers, wallets).
- Before the flag day this only **signals** (harmless preference). Enforcement (and the fork risk)
  begins at activation. **Decide deliberately, and keep a way to revert** (re-select a stock client).

This is an opt-in tool for people who understand and accept that trade-off.

## Maintenance
Rebase onto upstream `jstefanop/apolloapi-v2` when FutureBit cuts a release
(the change is small: the validation lists in `backend/switch_bitcoin_software.sh` +
`backend/update_system`, the `NodeSoftware` enum, `src/utils.js`, and the binary slot).
