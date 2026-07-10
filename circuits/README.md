# ShieldedPay — ZK circuits

The zero-knowledge half of ShieldedPay: the Circom circuit that lets a user
withdraw from the privacy pool **without revealing which deposit is theirs**,
while proving their deposit belongs to a "clean" association set. This directory
holds the circuit, its Merkle-proof library, the JavaScript test harness, and the
generator scripts for the on-chain fixtures.

- **Curve / proof system:** Groth16 over BN254 (alt_bn128).
- **Compiler:** Circom 2.2.3 (source pins `pragma circom 2.1.6;`).
- **Hasher:** Poseidon (circomlib), identical in the circuit, the JS harness, and the on-chain contract.
- **Size:** **21,735 constraints** (10,302 non-linear + 11,433 linear).
- **Trusted setup:** the public Hermez *Powers of Tau* ceremony — never a home-grown one.

> Educational / portfolio project. Not audited. Do not use with real funds.

---

## What the circuit proves

`withdraw.circom` implements `Withdraw(20)` — the `20` is the height of **both**
Merkle trees (2²⁰ ≈ 1M possible leaves, the same order of magnitude as classic
Tornado Cash). Given a public statement `(root, associationRoot, nullifierHash,
recipient, relayer, fee)` and a private witness, it proves — in one Groth16 proof
verified on-chain — all of the following, without leaking which deposit is being
spent:

1. **Knowledge of a deposit secret.** The prover knows `(nullifier, secret)` such
   that `commitment = Poseidon(nullifier, secret)`. That commitment is the
   "receipt" published on-chain at deposit time.

2. **State membership (like Tornado Cash).** That commitment is a leaf of the
   pool's deposit tree, whose current root is the public input `root`. This is a
   standard Merkle inclusion proof — it says "this is a real deposit" without
   saying which one.

3. **Association membership (the Privacy Pools mechanism).** The *same*
   commitment is *also* a leaf of the **association tree** whose root is
   `associationRoot` — the subset of deposits the ASP (Association Set Provider)
   has declared clean. This is the Privacy Pools design (Buterin/Illum/Nadler/
   Schär, 2023): an honest user proves membership in the clean set without
   revealing which deposit is theirs. If your funds trace back to a flagged
   source, the ASP never put them in this tree, and this half of the proof simply
   cannot be satisfied — there is no valid path to forge.

4. **Double-spend protection.** `nullifierHash = Poseidon(nullifier)` is a public
   input; the circuit enforces it equals the hash of the private `nullifier`. The
   contract records it as spent so the same deposit can't be withdrawn twice —
   and because it's a hash, it reveals nothing about which commitment it came
   from.

5. **Anti-tampering binding.** `recipient`, `relayer`, and `fee` are public
   inputs baked into the proof. A dishonest relayer who receives the proof cannot
   rewrite where the money goes or how large its own fee is: any change to these
   values invalidates verification. (In the source these are tied down with the
   `x * x` trick — a single constraint per signal — because Circom rejects a
   public signal that participates in no constraint. Same pattern as Tornado
   Cash; it adds nothing cryptographic beyond forcing the binding.)

The Merkle inclusion template (`lib/merkleProof.circom`) is reused for both trees
with the *same* leaf, which is what ties steps 2 and 3 to one and the same
deposit.

---

## File layout

```
circuits/
├── withdraw.circom              # main circuit: Withdraw(20)
├── lib/
│   └── merkleProof.circom       # Poseidon Merkle inclusion proof template
├── scripts/
│   ├── build.sh                 # reproducible DETERMINISTIC build (compile + verify constraints)
│   ├── genPoseidon.js           # Poseidon(2) deploy bytecode + zeros[0..20] for Solidity
│   └── genWithdrawFixture.js    # real Groth16 proof fixture for the Foundry tests
├── test/
│   ├── merkleTree.js            # JS Merkle harness (Poseidon, LEVELS=20, nothing-up-my-sleeve ZERO_VALUE)
│   └── proveWithdraw.test.js    # 4 tests: 1 valid + 3 invalid
├── package.json                 # snarkjs / circomlib / circomlibjs / @noble/hashes
└── build/                       # gitignored — heavy generated artifacts (see below)
    ├── withdraw.r1cs
    ├── withdraw.sym
    ├── withdraw_js/withdraw.wasm
    ├── pot15_final.ptau         # local copy of the Hermez ptau
    ├── withdraw_final.zkey
    └── verification_key.json
```

`build/` is gitignored (heavy, regenerable). So are `*.ptau`, `*.zkey`, `*.r1cs`,
`*.wtns`, and the `.bin/` circom binary. The **versioned** outputs of the pipeline
that live *outside* this directory are:

- `src/verifiers/WithdrawVerifier.sol` — the on-chain Groth16 verifier (a contract, so it's committed).
- `test/fixtures/poseidonBytecode.txt` and `test/fixtures/withdraw_valid.json` — small, committed so CI needs no snarkjs.
- `frontend/dapp/public/zk/withdraw_final.zkey` — committed by design so the browser can prove client-side (see the exception in `.gitignore`).

---

## Quick build (deterministic half)

If you only want to compile the circuit and confirm the constraint count, run the
helper — it installs circom if needed, compiles, and hard-fails unless the count
is exactly 21,735:

```bash
bash circuits/scripts/build.sh
```

This is idempotent and touches nothing that is committed. For the full pipeline —
including the parts that are **not** bit-for-bit reproducible — read on.

---

## Regenerating the full pipeline from scratch

All commands are run from Git Bash on Windows. `snarkjs` is invoked through the
local install (`node node_modules/snarkjs/cli.js`); `npx snarkjs ...` works too.

### 0. Install dependencies

```bash
cd circuits
npm install
```

### 1. Get the circom compiler (v2.2.3, iden3 prebuilt Windows binary)

The binary is not code; it lives at `.bin/circom.exe` and is gitignored.
`build.sh` downloads it automatically, or fetch it manually:

```bash
mkdir -p .bin
curl -fL -o .bin/circom.exe \
  https://github.com/iden3/circom/releases/download/v2.2.3/circom-windows-amd64.exe
.bin/circom.exe --version   # => circom compiler 2.2.3
```

### 2. Download and verify the Powers of Tau (`.ptau`)

We reuse the **public Hermez ceremony** — we never run our own trusted setup. The
`powersOfTau28_hez_final_15.ptau` file supports circuits up to 2¹⁵ constraints
(ours has 21,735 < 32,768). The Hermez S3 bucket returns 403; the Google Storage
mirror works:

```bash
curl -fL -o circuits/build/pot15_final.ptau \
  https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_15.ptau
```

Verify it before trusting it. Compute its Blake2b-512 hash and match it against
the official table published by iden3/snarkjs (the `snarkjs` README and the
`phase2` docs list the hash for each `powersOfTau28_hez_final_*.ptau`). The
download used here was verified to match that table **exactly**:

```bash
# Prints the ptau hash; snarkjs recomputes the Blake2b-512 and checks the
# internal contributions as part of `powersoftau verify` / zkey setup.
node circuits/node_modules/snarkjs/cli.js powersoftau verify circuits/build/pot15_final.ptau
```

If the hash does not match the official iden3/snarkjs table, **stop** — do not use
the file.

### 3. Compile the circuit (deterministic → 21,735 constraints)

```bash
cd circuits
../.bin/circom.exe withdraw.circom --r1cs --wasm --sym -o build -l node_modules
node node_modules/snarkjs/cli.js r1cs info build/withdraw.r1cs
# => # of Constraints: 21735
```

`-l node_modules` lets Circom resolve `circomlib/circuits/poseidon.circom`;
`lib/merkleProof.circom` resolves relative to `withdraw.circom`. This step is
fully deterministic (see the reproducibility note below).

### 4. Groth16 setup — phase 2 (NOT deterministic)

Derive the proving/verifying keys from the r1cs and the ptau, then add a phase-2
contribution. **The contribution injects fresh randomness**, so the resulting
`.zkey` differs on every run:

```bash
cd circuits
# initial zkey from the universal ptau
node node_modules/snarkjs/cli.js groth16 setup \
  build/withdraw.r1cs build/pot15_final.ptau build/withdraw_0000.zkey

# phase-2 contribution (random entropy — this is what breaks bit-reproducibility)
node node_modules/snarkjs/cli.js zkey contribute \
  build/withdraw_0000.zkey build/withdraw_final.zkey \
  --name="ShieldedPay phase2" -v -e="$(head -c 64 /dev/urandom | base64)"

# export the verifying key (JSON)
node node_modules/snarkjs/cli.js zkey export verificationkey \
  build/withdraw_final.zkey build/verification_key.json
```

### 5. Export the Solidity verifier

```bash
cd circuits
node node_modules/snarkjs/cli.js zkey export solidityverifier \
  build/withdraw_final.zkey ../src/verifiers/WithdrawVerifier.sol
```

> The committed `src/verifiers/WithdrawVerifier.sol` was generated this way. If
> you regenerate it, you will get a **different but equally valid** verifier — see
> below. Do not commit a regenerated verifier over the versioned one unless you
> mean to replace the whole keypair.

### 6. Publish artifacts for the browser dApp

The client proves in-browser, so it needs the wasm and the final zkey:

```bash
mkdir -p frontend/dapp/public/zk
cp circuits/build/withdraw_js/withdraw.wasm      frontend/dapp/public/zk/
cp circuits/build/withdraw_final.zkey            frontend/dapp/public/zk/
```

### 7. Generate the on-chain fixtures

```bash
node circuits/scripts/genPoseidon.js         # Poseidon(2) bytecode + zeros[] for Solidity
node circuits/scripts/genWithdrawFixture.js  # a REAL Groth16 proof, checked by the Foundry tests
```

`genPoseidon.js` writes `test/fixtures/poseidonBytecode.txt` (the Poseidon(2)
deploy bytecode from circomlibjs, byte-identical to what the harness and circuit
hash with) and prints the 21 `zeros[0..20]` constants for
`src/MerkleTreeWithHistory.sol`. `genWithdrawFixture.js` builds the happy-path
scenario (a deposit present in both the state and association trees) and writes a
real proof to `test/fixtures/withdraw_valid.json`, so the Foundry tests can verify
a genuine proof against the on-chain verifier without needing snarkjs in CI.

### 8. Run the circuit tests

```bash
cd circuits
npm test   # node --test — 4 tests: 1 valid + 3 invalid
```

---

## Reproducibility: what is deterministic and what is not

This matters for anyone auditing the repo, so it's worth stating plainly.

**Deterministic (independently verifiable).** The compilation in step 3 — the
`.r1cs`, `.sym`, and `.wasm` — is a pure function of the circuit source, the
circomlib version, and the compiler version. Anyone who compiles `withdraw.circom`
with Circom 2.2.3 and the same circomlib gets the **same 21,735 constraints**.
`build.sh` encodes exactly this check and fails loudly if the number drifts. You
do not have to trust us on the circuit size — recompile and see.

**Not deterministic (and that's fine).** The phase-2 setup in step 4 injects fresh
random entropy into the contribution. Re-running it produces a **different**
`.zkey`, a different `verification_key.json`, and therefore a **different**
`WithdrawVerifier.sol` — different verifying-key constants embedded in the
contract. This is not a bug and not a discrepancy to reconcile: **every** verifier
produced from an honest phase-2 contribution over the same r1cs and the same
public ptau is equally valid. Groth16's security does not depend on *which*
random contribution was used, only that at least one contributor was honest — and
here the heavy lifting (phase 1) is the public Hermez ceremony with many
contributors.

So the committed `src/verifiers/WithdrawVerifier.sol` is simply **one** valid
verifier among infinitely many. A reviewer who is suspicious of it can regenerate
their own end-to-end and confirm the system still works:

```bash
# Recompile (deterministic — must be 21735), redo phase 2 (fresh randomness),
# export YOUR verifier, regenerate the fixture, and run the tests against it.
bash circuits/scripts/build.sh
cd circuits
node node_modules/snarkjs/cli.js groth16 setup build/withdraw.r1cs build/pot15_final.ptau build/withdraw_0000.zkey
node node_modules/snarkjs/cli.js zkey contribute build/withdraw_0000.zkey build/withdraw_final.zkey --name="review" -v -e="$(head -c 64 /dev/urandom | base64)"
node node_modules/snarkjs/cli.js zkey export solidityverifier build/withdraw_final.zkey ../src/verifiers/WithdrawVerifier.sol
node scripts/genWithdrawFixture.js
cd .. && forge test        # the fixture + verifier you just generated verify cleanly
```

The proof produced against *your* keypair verifies against *your* verifier, and
the Foundry tests pass. That's the point: the security argument rests on the
public Hermez trusted setup and the deterministic, independently-recompilable
circuit — not on trusting the specific `.zkey` bytes we happened to commit.
