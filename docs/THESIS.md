# The compliant-privacy thesis

> Why ShieldedPay is built on **association sets**, not on a plain mixer — and why that is the version of on-chain privacy the ecosystem is actually funding right now.

This document is the *why* behind the code. If you only read one file in this repo to judge whether the author understands the space, read this one.

---

## One sentence

On-chain privacy and regulatory compliance are usually framed as opposites; **Privacy Pools** (Buterin, Illum, Nadler & Schär, 2023) shows they are not, and ShieldedPay is a working demonstration of that mechanism — stealth addresses for private *receiving*, and a shielded pool with **association sets** for private *transfer that a good actor can prove is clean*.

---

## The false dilemma

The first generation of on-chain privacy tools (Tornado Cash being the archetype) offered **anonymity as an undivided set**: you deposit, you withdraw to a fresh address, and the zero-knowledge proof hides which deposit was yours among *all* deposits. That is powerful — and it is also why the protocol was sanctioned by OFAC in August 2022. An honest user and a thief are mathematically indistinguishable inside the same anonymity set, so the tool cannot separate them, and regulators treated the whole set as tainted.

The naive reactions are both wrong:

- *"Privacy is the problem, remove it."* — Financial privacy is a legitimate default (you don't broadcast your salary to everyone who receives a payment from you). Killing it is not the fix.
- *"Compliance is the problem, ignore it."* — Tools that ignore it get delisted, sanctioned, and abandoned by the infrastructure (RPCs, front-ends, exchanges) that real users depend on.

## The insight: association sets

Privacy Pools breaks the dilemma with a second membership proof. When you withdraw you prove, in zero knowledge, **two** things at once:

1. **Membership in the pool** — your commitment is a leaf of the deposit Merkle tree (`root`). This is the classic Tornado guarantee: nobody learns *which* deposit is yours.
2. **Membership in an association set** — the *same* commitment is also a leaf of a smaller Merkle tree (`associationRoot`) that an **Association Set Provider (ASP)** has declared "clean" (e.g. after screening deposit provenance). Again in zero knowledge: you prove you belong to the clean subset **without revealing which member you are**.

The elegance is set-theoretic. An honest user can always point to a *large* association set — "everyone except the handful of known hacks" — and stay anonymous inside it. A thief cannot: any association set that includes their deposit exposes them by association, and any set that excludes it makes their withdrawal proof fail. Privacy and provenance stop being opposites; the user *chooses* the anonymity set they are willing to stand behind, and that choice is itself the compliance signal.

ShieldedPay implements exactly this dual proof. See [`circuits/withdraw.circom`](../circuits/withdraw.circom): two `MerkleTreeInclusionProof` components over the same `commitment`, one against `root` and one against `associationRoot`. The contract ([`src/PrivacyPool.sol`](../src/PrivacyPool.sol)) only accepts an `associationRoot` that the ASP ([`src/ASP.sol`](../src/ASP.sol)) has published, so a deposit that was never included in a clean set — because it *is* the flagged one — cannot withdraw. That exclusion path is exercised directly in the tests (`test_Withdraw_RevertsIf_AssociationRootNotPublished`).

---

## Why now: this is where the money and the core devs went

This is not a speculative bet on a future narrative. As of mid-2026 the compliant-privacy thesis is the one the serious players are backing:

- **Privacy Pools is live on Ethereum mainnet** (0xbow, since March 2025): ~$6M in volume, 1,500+ users, 1,186+ withdrawals — a deployed protocol, not a paper.
- **The Ethereum Foundation integrated Privacy Pools into its Kohaku wallet** — the first time privacy-preserving tech was built into core Ethereum tooling — and demonstrated it at the Cypherpunk Congress during **Devconnect in Buenos Aires**.
- **0xbow raised a $3.5M seed led by Coinbase Ventures** (November 2025).
- At the protocol layer, **EIP-8182** proposes a shielded pool *native to Ethereum* (one shared privacy pool for all wallets instead of fragmented apps), and the **Privacy Stewards of Ethereum (PSE)** initiative is the Foundation's umbrella for this work. Commentators call it privacy's **"HTTPS moment"** — the shift from a defensive niche tool to default infrastructure. The estimate for Devcon (Nov 2026) is that private transfers on Ethereum will be effectively "solved," with 30+ teams converging on a winning design.

Building on association sets means building in the same direction as Kohaku, EIP-8182 and the PSE — not against them.

---

## Where ShieldedPay sits

| | Tornado Cash | Railgun | **Privacy Pools / ShieldedPay** | Aztec |
|---|---|---|---|---|
| Privacy model | Fixed-denom mixer | Shielded balances (private state) | Fixed-denom pool **+ association set** | Full private zkRollup / private smart contracts |
| Compliance stance | None (undivided anonymity set) | Viewing keys / opt-in disclosure | **Provable exclusion of flagged funds, in ZK** | Programmable; app-defined |
| Breaks deposit↔withdraw link | Yes | Yes (in-pool transfers) | Yes | Yes |
| Proof system | Groth16 (circom) | Groth16 | Groth16 (circom) — *this repo* | PLONK-family (Noir) |
| "Good actor can prove clean" | ✗ | Partial | **✓ (the whole point)** | Depends on app |
| Scope of this repo | — | — | **Educational demo of the mechanism** | — |

ShieldedPay is deliberately positioned as the **Privacy Pools mechanism, implemented end-to-end and explained**, not as a competitor to any live protocol.

---

## What ShieldedPay demonstrates — and what it does not

**It demonstrates (honestly):**
- A working ZK circuit for the dual-membership (pool + association set) withdrawal proof, with nullifiers preventing double-spend and binding of `recipient`/`relayer`/`fee` against a malicious relayer.
- On-chain verification of a **real** Groth16 proof against a Poseidon Merkle tree whose root matches the off-chain tree bit-for-bit.
- **Client-side proving in the browser** — the withdrawal proof is generated on the user's machine; the secret `(nullifier, secret)` never leaves it.
- Stealth addresses (ERC-5564 + ERC-6538) as a complementary *receiving-privacy* layer, so the two pieces form one private-payments story rather than two disconnected demos.

**It does NOT claim to be (this is a portfolio / educational project):**
- **Audited.** It is not. Do not use it with real funds. See [`SECURITY.md`](../SECURITY.md).
- **A decentralized ASP.** The association-set provider here is a single `Ownable` account that publishes roots. A production ASP is a screening service or a governance process; that decentralization is explicitly out of scope and documented as a limitation, not hidden.
- **A trusted-setup ceremony of its own.** The Groth16 setup reuses the public **Perpetual Powers of Tau (Hermez)** `.ptau`, verified by its published hash — never a home-rolled setup presented as real.
- **Production anonymity guarantees.** Real anonymity depends on set size, relayer usage, timing analysis and gas-payment metadata — none of which a demo pool with a handful of deposits provides.

Being precise about the boundary is part of the thesis: the people worth impressing in this space can tell the difference between someone who *implemented the mechanism and understands its limits* and someone who shipped a mixer and called it privacy.

---

## References

- V. Buterin, J. Illum, M. Nadler, F. Schär, A. Soleimani — *Blockchain Privacy and Regulatory Compliance: Towards a Practical Equilibrium* (2023). The Privacy Pools paper.
- 0xbow — Privacy Pools (mainnet deployment; association-set implementation).
- Ethereum Foundation — Kohaku wallet; Privacy Stewards of Ethereum (PSE).
- EIP-8182 — protocol-level shielded pool for private ETH / ERC-20 transfers.
- ERC-5564 (stealth address scheme) and ERC-6538 (stealth meta-address registry).

*Figures cited (mainnet volume, users, funding) reflect public reporting as of mid-2026 and are context, not claims of this repo. See the project README for the verifiable, on-chain facts about ShieldedPay itself.*
