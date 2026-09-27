# BOLT11 amount mismatch mitigation

Status: implementation proposal, 2026-09-27. Branch: `fix/bolt11amounts`, created from `8f1c701` on `feat/mint-info-ui-refresh`.

## Intended behavior

For a full BOLT11 payment funded in sats, validate the mint's principal against the ceiling of the invoice's exact millisatoshi amount. Keep the invoice unchanged and account for fees separately.

Preserve MPP for whole-satoshi invoices, with exact, whole-satoshi shares and validation of every individual quote. For an invoice containing a millisatoshi remainder, require a full payment from one mint in this mitigation. Explain that restriction before requesting partial quotes.

This addresses a reproduced failure: Antifiat quoted 100,001 sats for a synthetic 100,000,001-msat invoice, while the pinned CashuSwift helper returned 100,000 sats. The original reported invoice is unavailable, so its failure is not conclusively attributed to this case.

## Evidence and constraints

- Macadamia's `BOLT11MeltQuoteSource.invoiceAmount` calls `CashuSwift.Bolt11.satAmount`, which truncates msats in the pinned CashuSwift 0.4.5. Its fallback uses `Double` and also truncates.
- The view compares only the aggregate quote principal against that amount. It does not validate each quote against its requested MPP share. For requested shares of 6 and 4 sats, responses of 7 and 3 currently pass the sum check.
- Quote fetches capture a selection but publish into the live dictionary without checking whether the invoice, selection or allocation has changed. Totals traverse all dictionary entries, including entries that can arrive from an obsolete request.
- The current allocation calculates `balance * totalMsat` with unchecked `Int` multiplication. Whole-sat apportionment can avoid the extra factor of 1,000 and use exact overflow-safe arithmetic.
- `MeltView.executeMelt` already validates quotes and selects all inputs, including input fees, before reserving any proofs. Keep that execution safeguard.
- Macadamia already directly depends on Bolt11 0.1.3. Its BOLT12 flow demonstrates explicit ceiling conversion and generation-scoped loading; no dependency upgrade is required for an application-level mitigation.

CDK's wallet requires the quote principal to equal `convert_to_ceil(requested_msat, unit)`. Its CLN and LND backends also round up. Nutshell rounds up full-payment principals in both 0.21.0 and the inspected current main.

NUT-15 expresses partial amounts in msats and requires their sum to equal the invoice amount. However, Nutshell's MPP validation compares the requested msats with the rounded quote converted back to msats. A sat-denominated partial request with a remainder therefore fails. This is an implementation compatibility restriction, not a prohibition on fractional-satoshi Lightning invoices.

Sources:

- [CDK wallet validation, revision 5cca094](https://github.com/cashubtc/cdk/blob/5cca0943cf8d05f50b1c73af3aee2c430d70f60d/crates/cdk/src/wallet/melt/bolt11.rs#L51-L70)
- [CDK LND quote rounding and boundary tests](https://github.com/cashubtc/cdk/blob/5cca0943cf8d05f50b1c73af3aee2c430d70f60d/crates/cdk-lnd/src/lib.rs#L1050-L1085)
- [Nutshell 0.21.0 full-payment quote conversion](https://github.com/cashubtc/nutshell/blob/0.21.0/cashu/lightning/lndrest.py#L520-L540)
- [Nutshell current MPP validation, revision c32cb38](https://github.com/cashubtc/nutshell/blob/c32cb388af7b5fffa2a9e310711f144595a31e15/cashu/mint/ledger.py#L1003-L1020)
- [NUT-15 payment coordination and msat units](https://github.com/cashubtc/nuts/blob/main/15.md)

## 1. Introduce a small immutable payment plan

Add an application-local `BOLT11PaymentPlan` next to the quote source. It should hold the original invoice, exact `amountMsat`, required `amountSat`, and active payment legs keyed by stable mint ID. Each leg records its requested msats and expected quote principal in sats. This is the common input to request construction, validation and readiness.

Decode the invoice once with the existing Bolt11 decoder. Convert its decoded integer amount and multiplier with checked integer arithmetic. Reject invalid, zero, amountless, sub-msat or unrepresentable amounts with a specific error before sending a request. Amountless support is outside this fix. Avoid the current helper's lossy fallback. The pinned decoder's raw amount/multiplier can be converted without relying on its unchecked large-value multiplication in `amountMillisatoshis`.

For positive, representable msats:

```swift
let requiredSats = msat / 1_000 + (msat % 1_000 == 0 ? 0 : 1)
```

Keep both units explicit in names and types. `requiredSats` is the ecash principal needed; it must never be multiplied back into the invoice's Lightning amount. Use checked sums and msat conversions throughout the plan.

## 2. Full payments

- Construct the existing BOLT11 request with `unit: "sat"`, the original invoice, and no MPP options. Skip allocation arithmetic entirely for a full payment.
- Require `quote.amount == requiredSats` and `quote.unit == "sat"`. Retain exact comparison; a different principal remains an error.
- Check an echoed invoice against the requested invoice, allowing BOLT11 case equivalence. An omitted echo remains compatible. Validate before filling missing local request metadata.
- Keep `feeReserve` separate. Use the existing checked quote arithmetic and `mint.select(amount: principal + feeReserve, unit: .sat)` to determine whether that mint can fund the payment, including proof input fees.
- Reuse existing expiry and execution checks. An insufficient fee balance must surface as insufficient funds, distinct from an amount mismatch.

## 3. Partial payments

For a whole-satoshi invoice, retain balance-weighted, largest-remainder apportionment in sats. Compute exact quotient/remainder pairs without overflowing intermediate multiplication, for example with unsigned full-width multiplication/division after validating positive bounds. Use a stable mint ordering to break ties. Convert each completed sat share to msats with checked multiplication.

Enforce these invariants before requesting quotes:

1. Every active leg has a positive allocation and an MPP-capable mint when multiple legs remain.
2. Each MPP share is a multiple of 1,000 msat and does not exceed the mint's available principal balance.
3. The sum of requested shares equals the original invoice's exact msat amount.
4. Each leg's expected principal is the ceiling of that leg's requested msats; under this mitigation it is an exact sat conversion.

Prune zero-value legs from the active plan, including quote-readiness and totals. If only one positive leg remains, issue an ordinary full-payment quote without MPP options. UI payment counts and allocations should reflect the active plan.

Send `options.mpp.amount` from the leg's exact msats. Validate each returned quote against that leg before constructing a payable bundle. Also check the request's method/unit and any invoice echo before converting a generic MPP response into the BOLT11 wrapper. A matching aggregate alone cannot establish a valid payment.

For invoices where `amountMsat % 1_000 != 0`:

- Automatic selection chooses a single eligible mint with sufficient principal balance, then checks its quoted fees.
- Manual selection also permits only a single payer; adding another payer must not initiate partial quotes.
- If no single mint can fund the payment, explain that this invoice needs one mint, with the option of obtaining a whole-satoshi invoice to use multiple balances.
- Suggested message: “This invoice includes a fraction of a satoshi. Pay it from one mint, or request an invoice for a whole number of sats to split the payment.”

Do not infer fractional-MPP capability from the mint's implementation/version string: NUT-15 support alone does not establish this compatibility. Supporting arbitrary fractional MPP shares across compatible backends can be a later change. That change must validate each rounded leg independently; the sum of per-leg ceilings can exceed the ceiling of the full invoice.

## 4. Bind quotes to the plan that requested them

Use a small testable loader, following the BOLT12 loader's generation pattern, or an equivalent scoped coordinator inside the new helper file.

- A load snapshots the invoice, active mint IDs, allocations and expected principals.
- Changing that snapshot, clearing input, changing selection or leaving the source invalidates the generation and removes any prior ready state immediately.
- Fetch using that immutable snapshot. Check its generation after every await and before publishing either results or errors. Cancellation is an optimization; correctness also needs the generation check.
- Publish a replacement result set for the current plan. All totals and ready bundles derive from its active legs only.
- Require all active quotes to pass per-leg validation, and all participating mints to cover their own quote plus fees, before publishing `.ready`.
- Surface the offending mint and expected/received amounts for a mismatch. Preserve the specific error instead of replacing it with “Unknown error.”

Keep this at new-quote negotiation. Existing saved pending melts retain their quoted amounts and recovery flow; do not reinterpret them using a newly chosen plan or compare every saved partial quote against the full invoice.

## 5. Proposed file scope

| File | Change |
| --- | --- |
| `macadamia/Wallet/Pay/BOLT11PaymentPlan.swift` (new) | Exact amount conversion, immutable per-mint plan, allocation/validation helpers, and testable quote loading |
| `macadamia/Wallet/Pay/BOLT11MeltQuoteSource.swift` | Consume the plan, apply full/MPP selection rules, and publish only current validated quotes |
| `macadamiaTests/BOLT11MeltTests.swift` (new) | Parser, plan, request, quote-validation and stale-response regressions |
| `macadamia/AppAssets/Localizable.xcstrings` | Specific unsupported-split and amount-mismatch messages |

Use the already-pinned decoder and existing networking APIs. No schema change or package-version change is needed. Leave proof reservation, melt execution and recovery in their existing owners. Avoid changing the semantics of the public `CashuSwift.Bolt11.satAmount` helper as a hidden dependency of this patch.

A separate CashuSwift follow-up can expose explicit exact-msat and ceiling-sat APIs and implement request-specific BOLT11 quote validation. That validation must use an MPP request's share, rather than the invoice total, and must account for the generic BOLT11 MPP path used by this app. Once available, the application-local conversion can delegate to it.

## 6. Regression coverage and acceptance criteria

Use deterministic signed invoices, an injected clock where expiry matters, and stubbed quote responses. Network/payment execution is unnecessary for these regressions.

| Area | Required cases |
| --- | --- |
| Rounding | 1, 999, 1,000, 1,001, 1,999, 2,000 and 100,000,001 msat; unchanged whole-sat amounts; large valid values |
| Parsing | Equivalent BOLT11 multipliers and uppercase encoding; malformed invoice/checksum; zero and amountless invoices; invalid sub-msat amount; conversion overflow |
| Full request | Original invoice preserved, `unit: "sat"`, no MPP options, exact expected ceiling accepted; lower/higher principal and wrong unit rejected |
| MPP allocation | Uneven balances, ties, leftover sats, zero balance/zero allocation, one remaining leg, and balances that would overflow the former intermediate product |
| MPP request | Positive whole-sat shares encoded as integer msats; exact sum equals invoice; every response validated against its own share |
| Compensating mismatches | Requested 6/4 sats with returned 7/3 rejected despite the correct aggregate; returning the full invoice amount for a partial quote rejected |
| Fractional MPP policy | Auto/manual attempts to split a fractional-sat invoice make no MPP requests; single-mint full quote remains permitted; clear failure when one mint cannot fund it |
| Funding | Each mint covers its own principal, Lightning reserve and input fees; ample aggregate balance cannot conceal a shortfall on one leg |
| Async state | Change invoice, selection or allocation while a load is suspended; old successes/errors cannot publish; returning to the same invoice/selection cannot revive an old generation |
| No side effects | Rejected quotes or unsupported splits never reach `.ready`, execute a melt, reserve proofs or consume derivation counters |

Run the focused BOLT11 tests and the existing BOLT12/payment-validation tests, then the repository's local unit tests with live-network cases excluded. Validate the UI manually for a full fractional-sat invoice, a supported whole-sat MPP invoice and a rejected fractional-sat split. Preserve the existing melt execution checks as the final protection against balances changing after quote loading.

Acceptance: the reproduced full-payment quote is accepted only at its correct ceiling principal; valid whole-sat MPP still works; mismatched individual quotes, unsupported fractional MPP and stale responses cannot enable payment.
