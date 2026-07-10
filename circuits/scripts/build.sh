#!/usr/bin/env bash
#
# build.sh — reproducible build of the DETERMINISTIC half of the ZK pipeline.
#
# What this does (and only this):
#   1. Ensures the circom v2.2.3 binary is present at .bin/circom.exe (downloads
#      the official iden3 prebuilt Windows release if missing).
#   2. Compiles circuits/withdraw.circom -> circuits/build/ (--r1cs --wasm --sym).
#   3. Reports the constraint count via `snarkjs r1cs info` and HARD-FAILS
#      (exit != 0) unless it is exactly 21735.
#
# What this does NOT do: it does not run the Powers-of-Tau phase-2 setup, it does
# not regenerate the .zkey, and it does not touch the versioned Solidity verifier
# (src/verifiers/WithdrawVerifier.sol). Those steps involve fresh randomness and
# are NOT reproducible bit-for-bit — see circuits/README.md ("Reproducibility:
# what is deterministic and what is not") for the full setup procedure.
#
# Run from Git Bash on Windows, from anywhere:
#   bash circuits/scripts/build.sh
#
# It is idempotent: re-running only re-downloads circom if the binary is absent
# and always recompiles into build/ (a gitignored directory).

set -euo pipefail

# --- Resolve paths (independent of the caller's cwd) ---------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CIRCUITS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$CIRCUITS_DIR/.." && pwd)"

CIRCOM_BIN="$REPO_ROOT/.bin/circom.exe"
BUILD_DIR="$CIRCUITS_DIR/build"
SNARKJS="$CIRCUITS_DIR/node_modules/snarkjs/cli.js"

# Official iden3 prebuilt circom v2.2.3 for Windows (x86-64).
# Release page: https://github.com/iden3/circom/releases/tag/v2.2.3
CIRCOM_VERSION="2.2.3"
CIRCOM_URL="https://github.com/iden3/circom/releases/download/v${CIRCOM_VERSION}/circom-windows-amd64.exe"

EXPECTED_CONSTRAINTS=21735

echo "==> ShieldedPay circuit build (deterministic half)"
echo "    repo:     $REPO_ROOT"
echo "    circuits: $CIRCUITS_DIR"

# --- Step 1: ensure circom binary ---------------------------------------------
if [ -x "$CIRCOM_BIN" ]; then
  echo "==> circom found: $CIRCOM_BIN ($("$CIRCOM_BIN" --version 2>&1 | head -n1))"
else
  echo "==> circom binary missing, downloading v${CIRCOM_VERSION} from iden3 releases..."
  echo "    $CIRCOM_URL"
  mkdir -p "$REPO_ROOT/.bin"
  curl -fL --retry 3 -o "$CIRCOM_BIN" "$CIRCOM_URL"
  chmod +x "$CIRCOM_BIN"
  echo "==> circom installed: $("$CIRCOM_BIN" --version 2>&1 | head -n1)"
fi

# --- Step 2: compile the circuit ----------------------------------------------
# circomlib is resolved from node_modules (-l), and lib/merkleProof.circom is
# resolved relative to withdraw.circom. This matches the original build.
mkdir -p "$BUILD_DIR"
echo "==> Compiling withdraw.circom -> build/ (--r1cs --wasm --sym)"
(
  cd "$CIRCUITS_DIR"
  "$CIRCOM_BIN" withdraw.circom --r1cs --wasm --sym -o build -l node_modules
)

# --- Step 3: report + verify constraint count ---------------------------------
if [ ! -f "$SNARKJS" ]; then
  echo "!! snarkjs not found at $SNARKJS — run 'npm install' in circuits/ first." >&2
  exit 1
fi

echo "==> snarkjs r1cs info build/withdraw.r1cs"
# Strip ANSI colour codes so the grep below is robust across terminals.
R1CS_INFO="$(node "$SNARKJS" r1cs info "$BUILD_DIR/withdraw.r1cs" | sed -r 's/\x1b\[[0-9;]*m//g')"
echo "$R1CS_INFO"

CONSTRAINTS="$(echo "$R1CS_INFO" | grep -oE '# of Constraints: [0-9]+' | grep -oE '[0-9]+')"

if [ "$CONSTRAINTS" != "$EXPECTED_CONSTRAINTS" ]; then
  echo "!! Constraint count mismatch: got '$CONSTRAINTS', expected $EXPECTED_CONSTRAINTS." >&2
  echo "!! The circuit is deterministic — a mismatch means the source or circomlib changed." >&2
  exit 1
fi

echo "==> OK: $CONSTRAINTS constraints (matches expected $EXPECTED_CONSTRAINTS)."
echo "==> Deterministic build complete."
echo "    Next (non-deterministic setup, see circuits/README.md): phase-2 groth16"
echo "    setup, export verifier, genPoseidon.js, genWithdrawFixture.js."
