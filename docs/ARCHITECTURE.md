# Architecture & the road to production

> ShieldedPay is a working demonstration of the Privacy Pools mechanism, not a
> production protocol. This document is the honest engineering account of the gap:
> where the demo's structural boundaries are, what it would take to cross each one,
> and — as importantly — where the right move is to *integrate* rather than build.
> It is written to be read by an engineer evaluating whether the author reasons
> about privacy systems at the level of trade-offs, not just tutorials.

---

## 1. Current architecture (and its deliberate boundaries)

The system is two layers that compose into one private-payments story:

- **Receiving privacy — stealth addresses (ERC-5564 / ERC-6538).** Off-chain ECDH
  (secp256k1) derives a fresh address per payment; on-chain contracts only *register*
  meta-addresses and *announce* payments. No link between a recipient's payments.
- **Transfer privacy — the pool.** Fixed-denomination deposits become leaves of a
  Poseidon Merkle tree. A withdrawal is a Groth16 proof of two Merkle memberships of
  the same commitment — one in the pool's state tree, one in an **association set**
  the ASP declared clean — plus a spent-nullifier check and a `recipient/relayer/fee`
  binding. The proof is generated **client-side**.

The demo makes four structural simplifications on purpose. Each is a boundary this
document exists to cross:

| Boundary | Demo | Why it's a boundary, not a bug |
|---|---|---|
| **ASP** | single `Ownable` publishing roots | Centralized trust: one key decides who is "clean". |
| **Amount** | fixed denomination (0.01 ETH) | No arbitrary-value transfers; anonymity = pool size only. |
| **Relayer** | passed in per call, bound in the proof | No relayer *network*; a withdrawer still needs gas somehow. |
| **Setup** | Groth16, one phase-2 contribution | Per-circuit trusted setup; ceremony is minimal. |

The point of naming them is that a production version is not "more of the same code"
— each boundary forces a genuine architectural choice with real trade-offs. The rest
of this document is those choices.

---

## 2. The road to production — design axes

Each axis: the problem, the realistic options, the trade-offs, and a recommendation.
Recommendations are opinionated on purpose — a design doc that refuses to choose is
not a design.

### Axis 1 — The ASP: from a single owner to credible neutrality

**Problem.** A single owner publishing association roots is a censorship and trust
chokepoint: it can refuse to include an honest deposit, or quietly include a dirty
one. The whole compliance claim rests on trusting that key.

**Options.**
1. *Multi-ASP, user-chosen (the Privacy Pools design).* The pool accepts a proof
   against *any* association root from a set of registered ASPs; the **user picks**
   which ASP's set to prove against at withdrawal time. Competition and choice
   replace a single trusted party — an honest user just picks any ASP whose set
   includes them; a bad actor finds no ASP that will.
2. *Governance-published roots.* A DAO / multisig / timelock publishes roots. Removes
   the single key but inherits governance latency and capture risk, and is slower
   than screening needs to be.
3. *Attestation-gated inclusion (EAS / on-chain attestations).* Inclusion in the
   clean set is itself gated by a verifiable attestation (e.g. a non-membership proof
   against a sanctions list, or a KYC attestation the user controls). Pushes the trust
   from "the ASP's judgment" to "a named, auditable attestation source".

**Trade-offs.** Option 1 is the most faithful to the Privacy Pools thesis and the
least trust-heavy, but it moves complexity to the client (which ASP do I trust? is my
deposit in their set?) and needs an ASP registry + off-chain infrastructure per ASP.
Option 3 is the most "compliant-by-construction" and the most interesting frontier,
but attestation ecosystems (EAS) are young and it risks re-introducing a gatekeeper.

**Recommendation.** Ship **Option 1 first** — make `associationRoot` acceptance a
lookup over a registry of ASPs rather than one contract, and let the withdrawal name
its ASP. It is the smallest change that removes the single point of trust and is
exactly the model 0xbow runs in production. Treat Option 3 as a *pluggable ASP
implementation* behind the same registry interface, not a competing design. This
keeps the pool agnostic and the trust model explicit.

*Concretely in this codebase:* `ASP.sol` already isolates root publication behind
`IASP`. The change is a `IASPRegistry` the pool consults, and moving `isKnownAssociationRoot`
from "one owner's map" to "any registered ASP's map" — the circuit is unchanged, since
it already proves membership against a *public* `associationRoot`.

### Axis 2 — Denomination: fixed pools vs. arbitrary amounts

**Problem.** Fixed denominations make deposits mutually indistinguishable (the source
of anonymity) but forbid arbitrary-value payments and fragment liquidity across
denominations. Real payments are arbitrary amounts.

**Options.**
1. *Multiple fixed denominations* (0.01 / 0.1 / 1 ETH pools). Cheap, keeps the current
   circuit, but splits the anonymity set per denomination and leaks coarse amount info.
2. *Shielded balances / UTXO model* (Railgun, Aztec, Zcash-style). Commitments encode
   *values*; withdrawal/transfer proves a balance equation (inputs = outputs + fee) in
   ZK. Enables arbitrary amounts and in-pool private transfers — a strictly more
   powerful primitive.
3. *Fixed denomination + amount splitting at the edges.* Keep the simple pool, handle
   arbitrary amounts by composing multiple notes off-chain.

**Trade-offs.** Option 2 is the real answer for a payments system, but it is a
*different and much harder circuit*: value-carrying commitments, range proofs to
prevent overflow/negative-value forgery, multi-input/multi-output trees, and a more
complex nullifier scheme. It roughly triples circuit and audit surface. Option 1 is a
weekend of work but a weak anonymity story. Option 3 pushes complexity to the client
and leaks the split pattern.

**Recommendation.** This is the fork that decides *what ShieldedPay is*. As a
**payments** protocol, Option 2 is required and everything else is a detour. As a
**compliance-mechanism demonstration** (what this repo is), the fixed-denomination
pool is the *correct* scope — it isolates the association-set idea without the
distraction of a balance circuit. The honest recommendation: **do not bolt shielded
balances onto this codebase.** If arbitrary amounts are the goal, that is a new
circuit and arguably a reason to build on Aztec/Noir (Axis 4) rather than extend a
Groth16 fixed-denomination pool.

### Axis 3 — Relayers & gas: who pays, and how private is that?

**Problem.** A fresh recipient address has no ETH for gas. If the withdrawer pays gas
from a funded address, that address links them — defeating the point. The demo binds a
`relayer` + `fee` into the proof so a third party can submit the tx and take the fee,
but it assumes a relayer exists.

**Options.**
1. *Relayer network.* A permissionless set of relayers monitor a mempool of withdrawal
   proofs and submit them for the bound fee. Standard in Tornado-style systems.
2. *Account abstraction (ERC-4337) / paymaster.* The withdrawal is a UserOp; a paymaster
   sponsors gas, reimbursed from the pool. Cleaner UX, aligns with where Ethereum
   wallets are going (and with Kohaku).
3. *Native protocol privacy (EIP-8182).* If shielded transfers become a protocol
   primitive, the gas/relayer problem is handled at the protocol layer.

**Trade-offs.** Option 1 is proven but needs relayer incentive design and a private
mempool (or relayers see the proof early — usually fine, since the proof binds the
recipient). Option 2 is the better long-term UX and composes with smart-account
wallets, but 4337 infrastructure is heavier and paymaster economics need care.

**Recommendation.** **Option 2 for a production build**, because it matches the
direction of the wallet ecosystem this would live inside (Kohaku is a smart-account
wallet) and removes the "run a relayer" operational burden. The proof's existing
`relayer/fee` binding generalizes cleanly to a paymaster address. Keep Option 1 as a
fallback for EOA users.

### Axis 4 — Proof system & trusted setup

**Problem.** Groth16 needs a *per-circuit* trusted setup (phase 2). Every circuit
change re-runs a ceremony. It is also the reason the verifier is circuit-specific.

**Options.**
1. *Stay on Groth16 + circom.* Smallest proofs, cheapest on-chain verification,
   maximal tooling maturity — but per-circuit setup and a hand-off to a ceremony on
   every change.
2. *Universal-setup SNARKs (PLONK / Halo2 / Honk).* One universal setup serves many
   circuits; circuit changes don't need a new ceremony. Slightly larger proofs / more
   gas.
3. *Noir (Aztec) / Barretenberg.* Modern DSL, universal setup, strong momentum in the
   privacy ecosystem, and a natural path if Axis 2 pushes toward shielded balances.

**Trade-offs.** Groth16 wins on gas and is right for a *stable* circuit deployed once.
The moment the circuit is expected to *evolve* (multi-ASP, shielded balances), the
per-circuit ceremony becomes friction and a universal setup pays off. Noir additionally
buys a much nicer language for the more complex circuits Axis 2 implies.

**Recommendation.** **Keep Groth16 for this fixed, shipped circuit** — it is the right
tool for a stable verifier and the cheapest to verify. **If the roadmap commits to
shielded balances (Axis 2), migrate to Noir**, not incrementally patch circom. The
proof system should follow the circuit's expected rate of change, not be chosen up front.

### Axis 5 — Scaling: tree size, batching, and where the pool lives

- **Tree height.** 2²⁰ leaves is demo-scale. Production wants larger trees and, more
  importantly, cheap insertion — Poseidon hashing on-chain per deposit is the gas cost
  that dominates. Options: sparse-Merkle optimizations, or moving insertion off-chain
  with a proof of correct insertion.
- **Batching / rollup.** Deposits and withdrawals batched and settled via a proof
  amortize per-op cost — this is the L2 shape.
- **Where it lives.** On L1 mainnet, gas makes a private pool expensive per op. On an
  L2 it is cheap but the anonymity set is per-L2. **EIP-8182** proposes a *shared*
  protocol-level pool so anonymity isn't fragmented across apps.

**Recommendation.** For anything beyond a demo, **deploy on an L2** (anonymity-set
fragmentation is the lesser evil vs. L1 gas killing usage), and design insertion to be
batchable from day one. But see Axis 6's strategic question before building a bespoke
pool at all.

### Axis 6 — Governance, upgradeability, and emergency response

The demo is intentionally immutable (no pause, no upgrade). Production needs an answer
for: a discovered circuit/verifier bug, ASP compromise, and parameter changes. Options
range from immutable-with-migration (safest, worst UX on bugs) to timelocked proxies
(flexible, larger trust surface). **Recommendation:** immutable core + upgradeable
*periphery* (ASP registry, relayer/paymaster config), with a timelock on the periphery
and a documented migration path for the core. Privacy protocols are exactly where
"upgradeable everything" is a liability — a malicious upgrade can exfiltrate secrets.

---

## 3. The strategic question: build vs. integrate

The most senior decision here is *not* which of the above to build — it is whether to
build a standalone pool at all.

As of 2026 the privacy stack is consolidating fast: Privacy Pools is live and
EF-integrated (Kohaku), EIP-8182 proposes a protocol-native shielded pool, and the PSE
initiative is converging ~30 teams toward a shared design for Devcon. In that world, a
new *standalone* pool competes for a fragmented anonymity set against protocols with
distribution and audits.

**The honest strategic read:**
- **Building a bespoke pool to production is the wrong bet** unless it has a genuine
  differentiator (a novel ASP model, a specific compliance regime, an app-specific
  anonymity set). Anonymity is a network effect; you don't want your own small one.
- **The high-leverage move is to build *on* the shared substrate** — e.g. an ASP
  implementation, a compliance-tooling layer, or a wallet integration on top of
  Privacy Pools / EIP-8182 — where you contribute to the large anonymity set instead
  of splitting it.

ShieldedPay's value is therefore as *demonstrated understanding of the mechanism*, and
the natural next project is not "ShieldedPay v2 the protocol" but "a component in the
ecosystem's shared pool." This document recommends against the vanity path of
productionizing the standalone pool.

---

## 4. A sequenced roadmap (if one were to build anyway)

Ordered by leverage-per-risk, each with a done-criterion:

1. **Multi-ASP registry** (Axis 1, Option 1). *Done:* withdrawal names an ASP; pool
   accepts any registered ASP's root; single-owner trust removed. Circuit unchanged.
2. **L2 deployment + batchable insertion** (Axis 5). *Done:* deposits/withdrawals on an
   L2 testnet with amortized insertion cost measured.
3. **Account-abstraction withdrawals** (Axis 3, Option 2). *Done:* a withdrawal is a
   sponsored UserOp; no EOA gas needed by the recipient.
4. **Decision gate — shielded balances?** (Axis 2). If yes → **restart the circuit in
   Noir** (Axis 4), do not extend circom. If no → the fixed-denomination pool is the
   product; stop here.
5. **Upgradeable periphery + timelock + audit** (Axis 6) before any real value.

The gate at step 4 is the real fork. Everything before it is reusable regardless.

---

## 5. Threat-model deltas for production

Beyond the demo's `SECURITY.md`, production must additionally address:

- **ASP collusion / censorship** — mitigated by multi-ASP choice (Axis 1); the residual
  is that *some* honest ASP must exist for a user.
- **Anonymity-set analysis** — timing, amount (if denominations multiply), gas-payer,
  and relayer metadata correlation. This is where most "private" systems actually leak;
  it is a systems problem, not a circuit problem.
- **Trusted-setup transparency** — a real ceremony with many public contributors and
  published transcript, not a single contribution.
- **Circuit audit** — the withdrawal circuit is the crown jewel; a soundness bug is a
  mint-money bug. Independent ZK audit is non-negotiable before value.
- **Upgrade-key compromise** — see Axis 6; in privacy protocols an upgrade can be an
  exfiltration vector.

---

## 6. What this demo is, and is not

**Is:** a correct, end-to-end, independently-reproducible implementation of the Privacy
Pools compliance mechanism — dual-membership ZK proof, on-chain verification, client-side
proving, and an integrated stealth-address layer — with an honest account of its own
limits.

**Is not:** a protocol you should deploy value into, or a bet that a standalone pool
should exist. Its purpose is to prove the mechanism is understood well enough to reason
about the production version — which, as Section 3 argues, is most valuably built *on*
the ecosystem's shared substrate, not beside it.

That distinction — knowing not just how to build the thing, but whether it should be
built standalone at all — is the actual deliverable.
