# macadamia → cdk-swift migration analysis

_Analysis date: 2026-04-13_
_cdk-swift version inspected: 0.16.0 (Package.swift binary target); README still advertises 0.14.2-rc.3 — version drift exists in the upstream repo._
_Clone location (outside project tree per instruction): `/tmp/cdk-swift-analysis/`_

---

## 1. Starting point — how macadamia uses CashuSwift today

macadamia is a SwiftData-backed iOS/macOS Cashu wallet with an iMessage extension. The main app and the extension share the same persistent store through the App Group `group.com.cypherbase.macadamia` and a `DatabaseManager` singleton. CashuSwift is consumed as a **stateless engine** — macadamia owns the database, transaction logging, proof state machine, coin selection, event model, fee accounting, transfer orchestration, and NUT-18 codec. CashuSwift is effectively called for: cryptographic primitives, network calls to mints, and DLEQ/lock verification.

Roughly **36 files** import CashuSwift. Grouped by feature area, these are the concrete API surfaces the wallet depends on:

| Area | CashuSwift symbols used by macadamia |
|---|---|
| Mint load / info | `CashuSwift.Mint`, `Mint.Info`, `Mint.loadInfo()`, `MintRepresenting`, `Keyset`, `numericalRepresentation(of:)` |
| Quotes | `QuoteRequest`, `Quote`, `Bolt11.MintQuote`, `Bolt11.MeltQuote`, `Bolt11.RequestMeltQuote.Options.MPP`, `Bolt11.satAmountFromInvoice(pr:)` |
| Send | `CashuSwift.send(inputs:mint:amount:seed:memo:lockToPublicKey:)`, `SendResult`, `Token`, `TokenVersion` |
| Receive | `CashuSwift.receive(token:of:seed:privateKey:)` |
| Melt | `CashuSwift.melt(quote:mint:proofs:blankOutputs:)`, `CashuSwift.meltState(for:with:blankOutputs:)`, `generateBlankOutputs()`, `BlankOutputSet` payload |
| Proof state | `CashuSwift.check(proofs, mint:)`, `ProofRepresenting`, `DLEQ` |
| Restore | `CashuSwift.restore(from:with:batchSize:)`, `KeysetRestoreResult` |
| DLEQ / lock | `Crypto.checkDLEQ(for:with:) → DLEQVerificationResult`, `Token.checkAllInputsLocked(to:) → LockVerificationResult` |
| NUT-18 | `PaymentRequest`, `Transport`, `NUT10Option` (round-tripped by custom `NUT26Codec.swift` TLV+bech32m) |
| Misc | `Token.sum()`, `Array<Proof>.sendable()`, `Unit` |

### macadamia’s persistent model (SwiftData `AppSchemaV1`)

- **`Wallet`** — root container; holds mnemonic+seed, `mints`, `proofs`, `events`.
- **`Mint`** — conforms to `CashuSwift.MintRepresenting`; stores `[CashuSwift.Keyset]`, `Mint.Info` decoded on demand via `loadInfo()`, owns derivation counters per keyset, `BlankOutputSet`s for fee return, proof arrays, and DP-based coin selection (`select`, `select_v2`, `selectWithoutFee`, `selectIncludingFee`, `transferLimits`).
- **`Proof`** — `.valid / .pending / .spent` state, stores `CashuSwift.DLEQ?`, `inputFeePPK`, links back to mint and wallet.
- **`Event`** — very rich kind enum: `pendingMint, mint, send, receive, pendingReceive, pendingMelt, melt, restore, drain, pendingTransfer, transfer`. Drives the transaction list UI and crash-recovery for mint/send/melt/transfer.
- **`BlankOutputSet`** — blinded outputs pre-generated for NUT-08 fee return on melts; persisted so an interrupted melt can be completed later.
- Hand-serialized blobs because SwiftData couldn’t encode the CashuSwift types directly: `bolt11MeltQuoteData`, `tokenData`, `blankOutputData`.

### Operations orchestrated by macadamia (not CashuSwift)

- `restore.swift` — drives per-mint restore as an `AsyncStream<MintRestoreResult>`, then hand-builds `Wallet`/`Mint`/`Proof` object graph with derivation counters via `assembleRestoredWallet()`.
- `send.swift` — calls `CashuSwift.send`, flips selected proofs `.valid → .pending → .spent` on success, writes a `send` `Event` with token data.
- `swap.swift` — `SwapManager` orchestrates `mint quote + melt quote + select + blank outputs`. Persists `pendingTransfer` events for crash recovery; `resumeTransfer()` re-hydrates and calls `CashuSwift.meltState`.
- `getQuote.swift` — dispatches on `Bolt11.MintQuote` vs `Bolt11.MeltQuote`, writes `pendingMint`/`pendingMelt` events.
- `Wallet/Pay/MeltView.swift` — parses invoices with `Bolt11.satAmountFromInvoice`, builds MPP options (`RequestMeltQuote.Options.MPP`) across mints.
- `Wallet/Redeem/RedeemView.swift` — calls `Crypto.checkDLEQ` and `Token.checkAllInputsLocked` before accepting a token.
- `NUT26Codec.swift` — custom bech32m+TLV encode/decode for `PaymentRequest` because CashuSwift hasn’t shipped NUT-26.

**Key architectural fact:** macadamia owns the proof state machine, and its UX, event log, transfer flows, and iMessage extension all assume direct mutation of SwiftData objects.

---

## 2. What cdk-swift (CashuDevKit) actually provides

`cdk-swift` ships a single `CashuDevKit` library built from a UniFFI-generated Swift facade around the Rust `cdk` crate, delivered as a prebuilt `cdkFFI.xcframework` binary target.

- **Package.swift** pins `cdkFFI.xcframework.zip` from `cdk-swift` release `v0.16.0` (checksum `9bff…9aa8`). Target platforms macOS 12 / iOS 15, Swift 5.5+. Links `resolv`.
- **Generated facade** `Sources/CashuDevKit/CashuDevKit.swift` — 21 k lines, almost entirely generated by UniFFI.

### The important types

- **`Wallet`** — one wallet _per mint_; init: `Wallet(mintUrl:, unit: CurrencyUnit, mnemonic: String, db: WalletSqliteDatabase, config: WalletConfig)` (or the lower-level `store: WalletStore` variant).
- **`WalletRepository`** — multi-mint coordinator: `init(mnemonic:, store: WalletStore)`, `createWallet(mintUrl:unit:config:)`, `getWallet(mintUrl:unit:)`, `getWallets()`, `hasMint(mintUrl:)`, `getBalances() → [WalletKey: Amount]`, `removeWallet(mintUrl:unit:)`.
- **`WalletStore`** — `.sqlite(path:)`, `.postgres(url:)`, `.custom(db: WalletDatabase)` (i.e., you can plug your own backend).
- **`WalletDatabase` protocol** — ~46 methods covering proofs, keysets, mint metadata, mint+melt quotes, transactions, KV store, **sagas** (for crash-recoverable multi-step operations), and **proof reservations** (for atomic send/melt state transitions). This is the seam for a custom backing store.
- **`WalletSqliteDatabase`** — ready-to-use; `init(filePath:)` and `newInMemory()`.
- **`Proof`** — struct with `amount, secret, c, keysetId, witness, dleq, p2pkE`.
- **`Token`** — `encode()`, `proofs(mintKeysets:)`, `p2pkPubkeys()`, `fromString(encodedToken:)`.
- **`PaymentRequest`** — **NUT-18 + NUT-26 native**: `fromString`, `toBech32String`, `toBip321(bolt11:bolt12:)`.
- **`Nuts`** struct — exposes `nut04, nut05, nut07Supported, nut08Supported, nut09Supported, nut10Supported, nut11Supported, nut12Supported, nut14Supported, nut20Supported, nut21, nut22, nut29`. **No `nut15`, no `nut18` advertisement field.**
- **`Restored`** — aggregate only: `spent: Amount`, `unspent: Amount`, `pending: Amount`. **Not per-keyset.**
- **`Transaction`** — `id, mintUrl, direction (.incoming/.outgoing), amount, fee, unit, memo, timestamp, …` — no analogue to macadamia’s 11-case `Event.Kind`.
- **`SendKind`** — `.onlineExact, .onlineTolerance, .offlineExact, .offlineTolerance`.
- **`SplitTarget`** — `.none, .value(amount), .values(amounts)`.
- **`FfiError`** — only `.Cdk(code: UInt32, errorMessage: String)` and `.Internal(errorMessage: String)`.
- **`SpendingConditions`** — `.p2pk(pubkey, Conditions?)`, `.htlc(hash, Conditions?)`.
- **Enums** — `ProofState{unspent,pending,spent,reserved,pendingSpent}`, `QuoteState{unpaid,paid,pending,issued}`.
- **Free functions** — `generateMnemonic()`, `decodeInvoice(invoiceStr:) → DecodedInvoice`, `proofY()`, `proofsTotalAmount()`, `proofSignP2pk()`, `proofHasDleq()`.

### Wallet method surface (partial)

`mintQuote`, `mint`, `prepareSend` / `PreparedSend.confirm`, `prepareMelt`, `meltQuote`, `melt`, `receive`, `restore`, `checkProofsSpent`, `listTransactions(direction:)`, `getTransaction(id:)`, `revertTransaction(id:)`, `verifyTokenDleq`, `subscribe(...)` (NUT-17 websocket), `getMintInfo`, …

### What this means architecturally

- **The wallet becomes stateful inside the library.** Proofs, state transitions, fee accounting, blank-output/fee-return lifecycle, and coin selection happen _inside_ `cdk` and persist to a DB the library owns.
- **`prepareSend → confirm`** is a two-phase commit. The prepared object _reserves_ proofs atomically via `WalletDatabase`. Abandoning mid-flow is a first-class operation (`revertTransaction`).
- **Sagas** provide built-in crash recovery for multi-step operations. This is exactly what macadamia today does by hand via `pendingMint`/`pendingMelt`/`pendingTransfer` events.
- **Per-mint `Wallet` object + `WalletRepository`** is the closest match to macadamia’s `Wallet → [Mint]` graph, but it’s _one Wallet per (mintUrl, unit)_ — a dual-unit mint is two Wallet instances.

---

## 3. Gap analysis table — macadamia needs vs cdk-swift capability

| # | Need | CashuSwift today | cdk-swift equivalent | Gap |
|---|---|---|---|---|
| 1 | Multi-mint container | `Wallet.mints: [Mint]` SwiftData | `WalletRepository` | Shape differs: one `Wallet` per (mintUrl, unit) in CDK. Dual-unit mints become 2 instances. Manageable. |
| 2 | MPP (NUT-15) support detection | Read `Mint.Info.nuts.nut15.methods` | `Nuts` struct **does not expose nut15** | **Blocker for MeltView MPP UI** unless upstream patched or worked around. |
| 3 | NUT-18 payment request parse/encode | CashuSwift types + custom `NUT26Codec.swift` | `PaymentRequest.fromString / .toBech32String / .toBip321` native | **Win** — delete `NUT26Codec.swift`. |
| 4 | Bolt11 amount extraction | `Bolt11.satAmountFromInvoice` | `decodeInvoice(invoiceStr:) → DecodedInvoice` | Direct replacement. |
| 5 | Keyset numerical representation (defence vs malicious mints) | `CashuSwift.numericalRepresentation(of:)` | Not exposed in public surface | **Gap** — used in `keysetCollisions(with:)`. Have to re-implement the hex→short-id math in Swift. |
| 6 | Custom DP coin selection | `Mint.select/select_v2` in SwiftData | `prepareSend` selects internally, using `SendKind` + `maxProofs` hints + `amountSplitTarget` | **Loss of control** — can no longer hand-tune selection for fee minimisation. |
| 7 | Manual proof state transitions (`.valid → .pending → .spent`) | Direct mutation of SwiftData objects | `prepareSend` → reservation; `confirm`/`revert` | **Conceptual shift** — UX code must stop mutating proofs. |
| 8 | Token V3 vs V4 selection | `TokenVersion` enum in `send.swift` | `Token.encode()` doesn’t expose a version parameter in the Swift facade (V4 only) | **Gap** — if you need to ship V3 for legacy peers. |
| 9 | DLEQ verification on redeem | `Crypto.checkDLEQ(for:with:) → DLEQVerificationResult` | `Wallet.verifyTokenDleq(token:)` or `proofHasDleq(proof:)` | Direct replacement, coarser result (no partial / mixed state). |
| 10 | Lock verification on redeem | `Token.checkAllInputsLocked(to:) → LockVerificationResult` | `Token.p2pkPubkeys()` — must compare yourself | **Minor gap** — rewrite the helper in a few lines. |
| 11 | P2PK / HTLC redeem | `receive(token:…privateKey:)` | `receive(token:, options: ReceiveOptions(p2pkSigningKeys:, preimages:))` | Direct replacement. |
| 12 | Per-mint restore with per-keyset counters | `CashuSwift.restore → [KeysetRestoreResult]` (per-keyset `derivationCounter`) | `Wallet.restore() → Restored` (aggregate only: spent/unspent/pending) | **Gap** — macadamia’s `Mint.increaseDerivationCounterForKeysetWithID` needs per-keyset counters. Inside CDK this is tracked in the DB but isn't returned through the facade. |
| 13 | Crash-recovery for mint/melt/transfer | Hand-rolled via `pendingMint/pendingMelt/pendingTransfer` events | Sagas inside CDK + `revertTransaction` | **Win** — delete most of `swap.swift` `resumeTransfer()` boilerplate. |
| 14 | Rich event log (11 kinds) | `Event.Kind` enum + `shortDescription/longDescription` | `Transaction{direction, amount, fee, memo, …}` | **Loss** — `pendingTransfer`, `drain`, `restore`, dual send/receive distinctions collapse. Need side table. |
| 15 | BlankOutputSet persistence for in-flight melt | `BlankOutputSet` SwiftData model + hand-serialized blob | Handled internally by CDK via sagas + WalletDatabase blank-output storage | **Win** — delete `BlankOutputSet`. |
| 16 | Error handling branches (insufficientFunds, network, generic) | Discriminated CashuSwift errors | `FfiError.Cdk(code, message)` + `.Internal(message)` | **Regression** — have to match on `code` or parse `message`. |
| 17 | iMessage extension sharing same store | `DatabaseManager` singleton pointing at App Group container | `WalletSqliteDatabase(filePath:)` pointing at same App-Group path | Works — but cdk’s SQLite must be safe for two processes. Needs verification (WAL + busy-timeout). |
| 18 | NUT-17 websocket subscriptions | Not used today | `Wallet.subscribe(...)` | **Feature unlock** — could replace polling in mint quote completion UX. |
| 19 | Bolt12 support | Not used today | `decodeInvoice` returns a `DecodedInvoice` enum that includes Bolt12 cases; `PaymentRequest.toBip321(bolt12:)` accepts Bolt12 | **Feature unlock**. |
| 20 | Multiple storage backends | Single SwiftData store | `WalletStore.sqlite/postgres/custom` | N/A for iOS but useful for a future macOS-native build. |

---

## 4. Pain points ranked by difficulty

### 4.1 Storage rewrite — biggest single piece of work
macadamia’s `AppSchemaV1` is the _hub_ of the app: Wallet → Mint → Proof → Event → BlankOutputSet, with SwiftData relationships. cdk-swift owns its own storage. Three realistic paths:

- **Path A (recommended): surrender to CDK SQLite.** Store balances, proofs, quotes, mint info, transactions inside `WalletSqliteDatabase`. Keep a thin SwiftData (or Core Data) side table keyed by `TransactionId` for event metadata that CDK doesn’t model (see 4.2). Simpler long term, single source of truth, no dual-write. Requires a one-shot migration on first launch that iterates existing proofs and re-inserts them via CDK.

- **Path B: adapter via `WalletStore.custom(db: WalletDatabase)`.** Implement all ~46 methods of `WalletDatabase` against the existing SwiftData schema. Maximum preservation of current UI and transaction history — but you inherit CDK’s data model in a Swift implementation and every upstream schema change becomes your problem. High cost, high ongoing maintenance burden.

- **Path C: dual-store (CDK for hot path, SwiftData for archive).** Proofs and in-flight state in CDK; keep SwiftData events as an append-only audit trail. Simplest to implement but risks divergence between the two stores and doubles the complexity of crash recovery (now both the CDK sagas and your event log can be mid-flight). Not recommended.

**Migration itself**: first-launch task reads existing proofs from SwiftData, calls `WalletRepository.createWallet(mintUrl:unit:)`, then inserts proofs via `WalletDatabase` add-proofs calls. Because macadamia persists derivation counters per keyset, those have to be re-applied too. `restore.swift`’s `assembleRestoredWallet` is a useful template for the shape of the insert loop, but the destination is CDK not SwiftData.

### 4.2 `Event.Kind` richness → `Transaction.direction` collapse
macadamia has eleven event kinds distinguishing mint / pending mint / send / receive / pending receive / melt / pending melt / restore / drain / transfer / pending transfer. CDK’s `Transaction` only has direction (incoming/outgoing) plus amount/fee/memo/timestamp. Losing this would gut the transaction list UI and make drains and transfers indistinguishable from send/receive.

**Mitigation**: side-table `EventExtras(transactionId: TransactionId, groupingId: UUID?, kind: Event.Kind, longDescription: String, memo: String?, preImage: String?, redeemed: Bool, visible: Bool)` keyed on CDK `TransactionId`. Read path: join CDK’s `listTransactions` with the local side table; write path: on every successful `confirm/revertTransaction`, insert the matching row. `Transfer` and `Drain` kinds become a pair of CDK transactions (one outgoing melt + one incoming mint) grouped by `groupingId`.

### 4.3 Two-phase `prepareSend / confirm` UX changes
Today `send.swift` flips proofs `.valid → .pending`, calls `CashuSwift.send`, then flips `.pending → .spent`. CDK’s flow is `prepareSend` (reserves atomically in the DB) → `PreparedSend.confirm` or abandon. Your view code must hold a `PreparedSend` handle (not a proof array) and must handle backgrounding: the reservation survives app restart, so on relaunch you need a UI entry point that calls `listTransactions(direction: .outgoing)` filtered by `pending` and either confirms or reverts.

Same shape applies to melt: `prepareMelt → PreparedMelt.confirm`. Again this is actually a _simplification_ vs the current `resumeTransfer()` code, but all of the call sites change.

### 4.4 Coin selection gated by the library
macadamia’s `select / select_v2 / selectWithoutFee / selectIncludingFee / transferLimits` in `Mint.swift` is DP-based and gives you fine control over fee minimisation and transfer-safe amounts. With CDK, selection happens inside `prepareSend`, tunable only via `SendKind`, `maxProofs`, and `amountSplitTarget`. If you care about hitting specific proof shapes (e.g., preserving large-denomination proofs), you lose a lever. This is mostly aesthetic for send, but **`transferLimits(for:)` — which tells the swap UI the minimum and maximum amount that can be transferred safely given fees and blank-output budget — has no direct equivalent**. You’d have to derive it empirically by calling `prepareMelt` with candidate amounts.

### 4.5 MPP (NUT-15) detection gap — `Nuts` struct omission
`MeltView.swift` currently reads `mint.info.nuts.nut15.methods` to decide whether MPP is supported before building a `Bolt11.RequestMeltQuote.Options.MPP` options object across mints. CDK’s `Nuts` struct on `MintInfo` **does not expose `nut15`** in the current binding. Three workarounds:

1. **Optimistic UI** — build the MPP quote anyway, handle the failure path if the mint rejects. Bad UX (user sees an error after selecting mints).
2. **Probe cache** — the first time a mint is loaded, try a small MPP quote and cache the capability. Wasteful and fragile.
3. **Upstream PR** — add `nut15` to the `Nuts` FFI struct. Almost certainly the right call; the Rust side already models it. This is the single most important upstream contribution to make before rolling cdk-swift out.

### 4.6 Keyset collision defence
`keysetCollisions(with:)` in macadamia uses `CashuSwift.numericalRepresentation(of:)` to detect a mint that ships two keysets whose short-ids collide in different hex forms — a known class of malicious-mint attack. CDK doesn’t expose an equivalent helper. Reimplement the short-id derivation in Swift (straightforward: parse the hex ID, drop the version byte, take the first 7 hex chars → u64). Put it in a `Keyset+Collision.swift` file and keep the defence; it’s not hard but it must not be forgotten during the port.

### 4.7 Error-handling rewrite
Every `catch let error as FfiError { case .generic / .insufficientFunds / .network }` site has to become `catch let e as FfiError { case .Cdk(let code, let msg): /* match on code */ }`. You need a table of CDK error codes → UI messages, and a test suite that asserts each one still renders the right alert. This is mechanical but pervasive.

### 4.8 TokenVersion V3 interop
If you currently let users emit V3 tokens for compatibility with older peers, CDK’s `Token.encode()` does not surface a version parameter in the Swift facade. Check whether macadamia still ships V3 emission as a user option; if yes, this is either a feature regression or a second upstream PR.

### 4.9 iMessage extension memory budget
The iMessage extension runs under a ~120 MB memory cap. Loading the full Rust `cdk` library plus the UniFFI runtime will cost more than CashuSwift (native Swift, compiled into the same binary). Budget for extension crashes during the spike phase: profile with Instruments → Allocations on a send flow from the extension. If it’s tight, consider making the extension read-only (show balance, receive-only) and routing send through the main app via a URL scheme.

### 4.10 Version drift in the upstream repo
The cdk-swift README documents `from: "0.14.2-rc.3"`. `Package.swift` actually pins the binary target from release `v0.16.0`. The docs clearly lag. Plan for upstream release hygiene to be part of your adoption cost — pin an exact version, test upgrades deliberately, and read the CDK Rust changelog, not the Swift README.

---

## 5. Hard gaps — things cdk-swift cannot yet replicate

These are the items with **no direct Swift API today**, in rough order of how much they hurt:

1. **NUT-15 capability advertisement** — missing from the `Nuts` struct (§4.5). Blocks MPP UI.
2. **Per-keyset restore counters** — `Restored` returns only aggregate spent/unspent/pending. macadamia’s per-keyset `derivationCounter` bookkeeping can’t be reconstructed from this result. Inside CDK the counters are persisted in the DB; you’d need a helper method to read them back, or accept that after a restore you simply trust the internal state.
3. **`numericalRepresentation` for keyset short-id** — not exposed; reimplement in Swift (§4.6).
4. **TokenVersion V3 emission** — `Token.encode()` has no version selector (§4.8).
5. **Granular DLEQ / lock verification results** — `Wallet.verifyTokenDleq` returns a single pass/fail; `checkDLEQ(for:with:) → DLEQVerificationResult` distinguishes `passed / notPassed / inputNotSupported`. The richer result is used by `RedeemView` to differentiate legitimately unverifiable tokens from failing ones.
6. **Fine-grained coin selection API** — no `prepareSendPreview(...)` that returns the candidate proof sets before committing (§4.4). `transferLimits(for:)` has no equivalent.
7. **`FfiError` variant richness** — collapsed to two cases; no `insufficientFunds`, no `network`, no `invalidToken` branches in Swift (§4.7).
8. **Event kind richness** — no pendingTransfer / drain / per-flow distinction in `Transaction` (§4.2).
9. **BlankOutputSet introspection** — CDK handles fee-return blank outputs internally but does not expose them as a Swift-observable object. macadamia’s current UI doesn’t show them to the user either, so this is a non-issue today; flagged for completeness.
10. **Deterministic re-emission of the same token bytes** — CashuSwift’s `Token` type is Codable and its serialization is stable across versions. CDK’s `Token` goes through the FFI layer; any round-trip that depends on byte-identical reencoding (unlikely, but audit the persistence of sent tokens in `tokenData` blobs) needs verification.

None of these are showstoppers if you’re willing to either (a) upstream a patch, (b) work around in Swift, or (c) lose the feature.

---

## 6. Recommended migration plan

Five phases, each independently shippable or revertible.

### Phase 0 — spike (1 day)
- Add `cdk-swift` as a _parallel_ dependency (keep CashuSwift).
- Stand up a `WalletRepository(mnemonic:, store: .sqlite(path: appGroupURL.appending("cdk.sqlite")))` behind a debug build flag.
- Create a single wallet for one mint, call `getMintInfo`, `mintQuote`, and `listTransactions`. Confirm the binary target loads, the App Group path works, and memory is acceptable in the iMessage extension.
- **Gate criterion**: does the iMessage extension stay under its memory cap while holding an open CDK wallet? If not, reshape the plan so that the extension stays on CashuSwift and only the main app migrates.

### Phase 1 — parallel read path (1 week)
- Implement a read-only `CDKReadAdapter` that mirrors the current SwiftData `Wallet.balance / Mint.proofs / listTransactions` views from CDK data, without mutating either store.
- Put it behind a debug toggle. In debug, show both balances side-by-side in a developer menu. Compare against SwiftData state.
- Write the **one-shot migration script**: iterate all SwiftData proofs, insert into CDK, replay derivation counters. Run on a copy of the prod store first.

### Phase 2 — switch the _read_ model (1–2 weeks)
- WalletView, MintDetail, and TransactionList start reading from CDK instead of SwiftData. Writes still go to SwiftData.
- Introduce the `EventExtras` side table (§4.2); populate it alongside existing SwiftData Event writes during this phase so it’s already warm when the write path switches.
- Fix the per-keyset restore gap: either upstream a `perKeyset: [KeysetRestored]` field, or accept the loss and document it.
- **Gate criterion**: UI looks identical to users; transaction list still distinguishes all 11 kinds via EventExtras.

### Phase 3 — write path: mint, send, receive (2–3 weeks)
- Rewrite `getQuote.swift` mint quote flow to call `Wallet.mintQuote` then `Wallet.mint`.
- Rewrite `send.swift` to `prepareSend → PreparedSend.confirm` or abandon. Delete the manual `.valid → .pending → .spent` transitions.
- Rewrite `WalletView.receive` to `Wallet.receive(token:, options: ReceiveOptions(p2pkSigningKeys:, preimages:))`.
- Delete `NUT26Codec.swift` in favour of `PaymentRequest.fromString / toBech32String`.
- Replace `Crypto.checkDLEQ` / `checkAllInputsLocked` with `verifyTokenDleq` + a `Token.p2pkPubkeys()` helper.
- Double-write SwiftData Event rows until the UI migration is complete — source of truth becomes CDK + EventExtras, but SwiftData stays as a disaster-recovery backup during this phase.

### Phase 4 — write path: melt, swap, restore (2–3 weeks)
- Rewrite `MeltView.swift` to `prepareMelt → PreparedMelt.confirm`. Handle the NUT-15 gap: either ship the upstream `Nuts.nut15` patch and gate MPP on it, or fall back to optimistic-UI (§4.5).
- Rewrite `SwapManager.swap` as two linked CDK operations grouped by `groupingId` in EventExtras. Delete `BlankOutputSet` — CDK handles it. Delete `resumeTransfer()` — CDK sagas handle it.
- Rewrite `restore.swift`: `Wallet.restore()` per mint inside a `WalletRepository` loop. Accept aggregate totals or add the per-keyset helper.
- Run the one-shot migration script on real user stores in a beta build. Provide an in-app “reset to safe state” escape hatch.

### Phase 5 — cleanup (1 week)
- Remove CashuSwift from Package.swift (3 targets: app, tests, extension).
- Remove SwiftData `Proof`, `BlankOutputSet`; keep `Wallet`, `Mint`, `EventExtras` only as local metadata caches. Or delete SwiftData entirely if EventExtras can live in CDK’s `kvStore` — arguable, but probably not worth the risk on the first cut.
- Delete now-dead orchestration code: `resumeTransfer`, `select/select_v2`, `selectWithoutFee`, `selectIncludingFee`, `transferLimits` (replaced by `prepareSend`/`prepareMelt`).
- Update tests to use `WalletSqliteDatabase.newInMemory()` instead of the SwiftData in-memory store.

**Total**: ~8–10 weeks for a single developer, assuming no major upstream patch turnarounds. The single biggest risk is **the iMessage extension memory budget** — decide that in Phase 0 before committing to the full plan.

---

## 7. Things to confirm before committing

1. **Is cdk-swift's UniFFI runtime small enough for the iMessage extension?** Phase 0 gate. If not, the extension stays on CashuSwift or becomes read-only.
2. **Is `WalletSqliteDatabase` safe for concurrent access from main app + messages extension sharing an App Group sqlite file?** Must verify WAL mode, busy-timeout, and cross-process file locking. If not, you need a single-writer model where the extension proxies writes through the main app.
3. **Will upstream accept a `Nuts.nut15` patch on a reasonable timeline?** Determines whether MPP keeps working during migration or is temporarily disabled.
4. **Does macadamia still need to emit V3 tokens for legacy peers?** If yes, either upstream a `Token.encode(version:)` parameter or block on that upstream change.

---

## Appendix — file inventory

### macadamia files touched by the migration

- `macadamia/PersistentModelV1/PersistentModelV1.swift` — schema (Wallet, Mint, Proof, Event, BlankOutputSet)
- `macadamia/PersistentModelV1/Mint.swift` — coin selection, derivation counters, transfer limits
- `macadamia/PersistentModelV1/Operations/send.swift`
- `macadamia/PersistentModelV1/Operations/swap.swift` (`SwapManager`)
- `macadamia/PersistentModelV1/Operations/restore.swift`
- `macadamia/PersistentModelV1/Operations/getQuote.swift`
- `macadamia/Misc/NUT26Codec.swift` (deletable after migration)
- `macadamia/Wallet/WalletView.swift`
- `macadamia/Wallet/Pay/MeltView.swift`
- `macadamia/Wallet/Redeem/RedeemView.swift`
- `macadamia/macadamia.xcodeproj/project.pbxproj` — 3 CashuSwift package references (main app, tests, messages extension)

### cdk-swift surfaces to know

- `Sources/CashuDevKit/CashuDevKit.swift` — single generated facade (21 k lines)
- `Package.swift` — binary target, v0.16.0 xcframework, iOS 15 / macOS 12
- `Tests/CashuDevKitTests/CashuDevKitTests.swift` — example integration tests against an in-memory db, useful templates for the new macadamia test suite
