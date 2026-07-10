# Designing a decentralized Association Set Provider

> The component that decides whether "compliant privacy" is **credibly neutral** or
> just a new trusted chokepoint. In `ShieldedPay` (and in 0xbow's production Privacy
> Pools today) the ASP is effectively one operator publishing roots. This document
> designs what it takes to decentralize it — the highest-leverage buildable component
> *on top of* the shared privacy pool, and an open problem the ecosystem has not
> fully solved.

This is a design blueprint, not shipped code. It is written to be built.

---

## 1. What the ASP is, and why decentralizing it is the hard part

Privacy Pools splits "is this a real deposit?" (the pool's state tree) from "is this
deposit *clean*?" (the **association set**). The Association Set Provider is whoever
constructs that clean set and publishes its Merkle root on-chain, against which
withdrawers prove membership in zero knowledge.

That makes the ASP the single most trust-laden component in the whole design:

- If the ASP **censors** — refuses to include an honest deposit — that user cannot
  withdraw privately (or at all, if no other ASP serves them).
- If the ASP is **permissive** — includes dirty funds — the compliance claim is void.
- The ASP sees the *public* deposit graph (it screens on-chain provenance), so it must
  be designed so it **learns nothing that de-anonymizes** withdrawers beyond what's
  already public.

The cryptography (the ZK proof of dual membership) is the *easy, solved* part. The ASP
is a **mechanism-design and data-availability** problem wearing a smart-contract
costume. That's why it's the interesting thing to build.

---

## 2. Requirements

A credibly-neutral ASP must satisfy, roughly in priority order:

1. **Censorship-resistance.** No single party can permanently exclude an honest deposit.
2. **Verifiability of inclusion/exclusion.** Anyone can check *why* a deposit is in or
   out of a set, against public rules — not opaque judgment.
3. **Data availability.** The full set (or enough to reconstruct it) must be public, or
   users can't build their withdrawal proofs. Publishing a root without the data is a
   silent censorship vector.
4. **Privacy preservation.** The screening process must not leak anything that links a
   deposit to a withdrawal.
5. **Timeliness.** New honest deposits get into a clean set fast enough to be usable.
6. **Accountability.** A misbehaving ASP (censoring or permissive) can be detected and
   penalized.

Note the tension baked in: (1) and (2) pull toward *objective, mechanical* rules;
real-world compliance pulls toward *discretionary* judgment. The design's job is to
push as much as possible onto objective rules and quarantine the irreducible discretion.

---

## 3. The core tensions (name them before designing)

- **Censorship vs. permissiveness.** Tightening the set to exclude dirty funds risks
  excluding honest ones; loosening it does the reverse. There is no single "correct"
  set — which argues for *many* sets and user choice, not one canonical set.
- **Objectivity vs. discretion.** "Exclude funds traceable to the Ronin hacker" is
  near-objective. "Exclude suspicious funds" is not. The former can be a public rule;
  the latter needs a named, accountable attester.
- **Privacy vs. screening.** Screening reads the public graph — fine — but the *output*
  must be a set that reveals nothing about who withdraws.
- **Data availability vs. cost.** Full sets can be large; publishing them cheaply and
  durably is a real constraint.

---

## 4. Architecture — five layers

Decompose the ASP into layers so each can decentralize at its own pace.

```
   ┌──────────────────────────────────────────────────────────────┐
 5 │ Accountability: staking / slashing / reputation of ASPs        │
   ├──────────────────────────────────────────────────────────────┤
 4 │ Flagging governance: what counts as "dirty" (rules + attest.)  │
   ├──────────────────────────────────────────────────────────────┤
 3 │ On-chain: ASP registry + root publication (MULTI-ASP)          │
   ├──────────────────────────────────────────────────────────────┤
 2 │ Data availability: publish the sets (IPFS/Arweave/blobs)       │
   ├──────────────────────────────────────────────────────────────┤
 1 │ Set construction: deterministic provenance/taint over the graph│
   └──────────────────────────────────────────────────────────────┘
```

### Layer 1 — Set construction (deterministic, auditable)

The ASP computes, off-chain, a taint analysis over the *public* deposit/transaction
graph: starting from a set of **flagged source addresses** (Layer 4), it propagates
taint forward and marks every pool deposit whose provenance traces to a flagged source.
The clean association set = all deposits **minus** the tainted ones.

The critical design choice: **make this a pure function** of `(pool deposit history,
flagged-source list, propagation rules)`. If the rules are public and deterministic,
anyone can recompute the set and verify the ASP didn't cheat — the ASP becomes a
*replicator of a public computation*, not an oracle of opinion. Different propagation
policies (e.g. taint-decay, minimum-hop cutoffs) become different, labeled ASPs.

### Layer 2 — Data availability

The set is only useful if withdrawers can fetch it to build their Merkle path.
Publish, per set version:
- the ordered list of included commitments (or a compact structure to rebuild the tree),
- pinned to **IPFS/Arweave** (content-addressed) or posted to an **L2 blob / DA layer**,
- with the content hash committed on-chain next to the root.

This closes the "publish a root but withhold the data" attack: a root whose data isn't
retrievable is, by rule, not a valid set (see Layer 5 slashing). Content-addressing means
the on-chain hash *is* the availability commitment.

### Layer 3 — On-chain: registry + multi-ASP root publication

Replace the single `Ownable` ASP with:
- **`IASPRegistry`** — a registry where ASPs register (with a stake, Layer 5) and are
  discoverable. Each ASP has an id, metadata URI (its policy), and a stake.
- **Per-ASP root history** — each ASP publishes `(root, dataHash, timestamp)`; the pool
  accepts a withdrawal whose `associationRoot` matches *any recent root of any
  registered, non-slashed ASP the user selected*.
- The pool circuit is **unchanged**: it already proves membership against a *public*
  `associationRoot`. Decentralization lives entirely in *which* roots the pool will
  honor — a registry lookup, not a circuit change. This is the key architectural win:
  the hard cryptography is untouched.

*User selection:* the withdrawal names the ASP (or the pool accepts the union of roots).
Naming the ASP keeps anonymity sets from silently merging across incompatible policies.

### Layer 4 — Flagging governance: what counts as "dirty"

This is the irreducible-discretion layer; the goal is to *minimize and name* it.
Options, composable:
- **Public rule-sets:** flagged-source lists that are themselves on-chain or attested,
  e.g. "addresses in OFAC SDN as published by attester X", "addresses in the Ronin
  exploit as attested by the protocol". Each list has a named, accountable maintainer.
- **Attestation-based (EAS):** flags are on-chain attestations from identified
  attesters; an ASP's policy declares which attesters it honors. This turns "trust the
  ASP's judgment" into "trust these named attesters", which is auditable and revocable.
- **Dispute windows:** a newly-flagged deposit can be challenged before it propagates,
  with an on-chain adjudication (optimistic: flagged unless successfully disputed, or
  vice-versa per policy).

The design principle: an ASP is defined by *(propagation rule, honored attester set,
dispute policy)* — all public. Two ASPs that differ only in honored attesters are
different products users can choose between.

### Layer 5 — Accountability: staking, slashing, reputation

Registered ASPs post a **stake**. They can be slashed by on-chain-provable faults:
- **Data withholding** — published a root whose `dataHash` content is unavailable / doesn't
  match (provable by anyone who reconstructs and hashes).
- **Rule violation** — the published set doesn't match the deterministic recomputation
  from the declared rules + flag lists (Layer 1 makes this checkable; a fraud proof
  submits the discrepancy).
- Censorship is harder to slash objectively (you can't prove intent), so it's handled by
  **exit**: users pick another ASP, and persistent censorship shows up as lost market
  share + reputation. Reputation = uptime, set freshness, stake, age — surfaced to users
  choosing an ASP.

Slashing needs a fraud-proof adjudicator; the deterministic set construction (Layer 1)
is what makes "the set is wrong" a *provable* statement rather than a matter of opinion.

---

## 5. User flow (withdrawer's perspective)

1. Deposit as usual → commitment in the pool's state tree.
2. Wait for an ASP whose policy you accept to include your commitment in a clean set
   (fetch candidate sets from Layer 2; check inclusion locally).
3. Pick that ASP; fetch the set data; build your Merkle path against its `associationRoot`.
4. Generate the withdrawal proof client-side (unchanged from the current pool).
5. Withdraw, naming the ASP; the pool validates the root against the registry.

The only new user-facing concept is **choosing an ASP** — which is also the entire point:
the user, not a central party, decides which anonymity set + policy they stand behind.

---

## 6. Interfaces (sketch)

```solidity
interface IASPRegistry {
    function register(bytes32 policyHash, string calldata metadataURI) external payable; // stakes
    function isActive(uint256 aspId) external view returns (bool);      // registered & not slashed
    function publishRoot(uint256 aspId, uint256 root, bytes32 dataHash) external;
    function isKnownRoot(uint256 aspId, uint256 root) external view returns (bool); // within recent history
    function slash(uint256 aspId, bytes calldata fraudProof) external;  // data-withholding / rule-violation
}
```

The pool's withdrawal check becomes: `registry.isActive(aspId) && registry.isKnownRoot(aspId, associationRoot)`
— a two-line change from today's single-owner `asp.isKnownAssociationRoot(...)`.

---

## 7. Progressive decentralization (don't try to ship layer 5 first)

1. **Multi-ASP registry, permissioned set of ASPs, stake but no slashing.** Immediately
   removes the *single* trusted party; users get choice. Smallest real win.
2. **Data-availability commitment + withholding slashing.** Makes "publish a root, hide
   the data" unprofitable.
3. **Deterministic set construction + rule-violation fraud proofs.** Turns the set into
   a verifiable computation; enables real slashing.
4. **Attestation-based flagging (EAS) + dispute windows.** Decentralizes the "what's
   dirty" judgment.
5. **Permissionless ASP registration + reputation market.** Full open competition.

Each step is independently valuable and shippable. Most of the trust reduction is in
steps 1–3.

---

## 8. Threat model (ASP-specific)

- **Censoring ASP** → mitigated by multi-ASP choice; residual: *some* honest ASP must
  serve the user. Fully permissionless registration (step 5) makes this a liveness
  assumption, not a trust one.
- **Permissive ASP** (includes dirty funds) → its policy is public; users/verifiers who
  care simply don't accept its roots. The market prices its sets accordingly.
- **Data withholding** → slashable via the DA commitment.
- **Rule-violation** (set ≠ declared rules) → slashable via fraud proof over the
  deterministic construction.
- **Attester capture** (Layer 4) → an attester goes rogue; mitigated because ASPs honor
  *named* attester sets, so users route around a captured attester by choosing ASPs that
  don't honor it.
- **Anonymity-set fragmentation** → too many niche ASPs shatter the anonymity set. Real
  tension; mitigated by a few Schelling-point policies most honest users converge on
  (large "everyone minus known hacks" sets).
- **Deanonymization via set membership** → an ASP that publishes a set of *one* isolates
  a user. Enforce a minimum set size and reject degenerate sets at the registry.

---

## 9. Relationship to the shared ecosystem (EIP-8182 / PSE / 0xbow)

This is deliberately designed as a component that plugs into a **shared** pool, not a
private fork:
- Against **0xbow's Privacy Pools**, this is a more decentralized ASP layer for the same
  mechanism — a credibly-neutral alternative to their operator-run ASP.
- Against **EIP-8182's** protocol-level shielded pool, the ASP registry is exactly the
  kind of periphery that a protocol pool would *not* mandate but *would* want an open
  market of — associations are policy, and policy shouldn't be hard-coded into the
  protocol.
- It's aligned with **PSE**'s direction: keep the base layer neutral, push
  policy/compliance to an open, accountable periphery.

That alignment is the strategic point: the anonymity set lives in the shared pool (big,
valuable); the *policy* over it is where a credibly-neutral ASP adds value without
fragmenting privacy.

---

## 10. What's genuinely hard (open problems, stated honestly)

- **Provable non-censorship.** Slashing catches data-withholding and rule-violation, but
  *intentional* censorship (an ASP that just never gets around to including you) is only
  handled by exit + reputation, not cryptographic guarantee. Permissionless registration
  reduces it to a liveness assumption; eliminating it entirely is unsolved.
- **Objective "dirty".** Reducing compliance to public, deterministic rules works for
  known hacks; it does not capture the discretionary, jurisdiction-specific reality of
  real AML. Layer 4 quarantines this but doesn't dissolve it.
- **DA cost at scale.** Large, frequently-updated sets are non-trivial to keep available
  cheaply; blob economics and incremental-set encodings need real work.
- **Cross-ASP anonymity.** The more policies exist, the more the anonymity set splits.
  The equilibrium number of ASPs is an economic question, not a technical one.

Naming these is the point: a decentralized ASP is buildable and clearly better than a
single operator, but "trustless compliant privacy" is not a solved problem — it's a
frontier, and this is a credible architecture for advancing on it.
