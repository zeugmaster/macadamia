# BOLT11 amount handling

BOLT11 invoice amounts are exact millisatoshis. Sat-denominated ecash must cover them by rounding the principal up to a whole satoshi, with fees accounted for separately.

A quote-only probe reproduced the mismatch: Antifiat returned 100,001 sats for a synthetic 100,000,001-msat invoice, while the pinned CashuSwift helper returned 100,000 sats. The originally reported invoice was unavailable, so its failure could not be conclusively attributed to this case.

## Payment rules

| Payment | Request and validation |
| --- | --- |
| Full payment | Preserve the original invoice, omit MPP options, and require the quote principal to equal `msat / 1_000 + (msat % 1_000 == 0 ? 0 : 1)`. |
| Whole-satoshi MPP | Allocate positive whole-sat shares, send each share as integer msats, and require every quote to match its requested share. Shares must sum exactly to the invoice. |
| Fractional-satoshi invoice | Require one mint with sufficient balance. Explain this restriction before requesting any partial quotes. |

CDK validates the ceiling of the requested msat amount. Nutshell also rounds up full payments, but its MPP validation compares requested msats to the sat quote converted back to msats. A partial request with a millisatoshi remainder therefore fails. Requiring whole-sat MPP shares provides compatibility with both implementations; NUT-15 support alone does not establish support for fractional-sat shares.

## Implementation

`BOLT11PaymentPlan.swift` decodes the signed invoice with the existing Bolt11 dependency and converts its integer amount/multiplier using checked arithmetic. Invalid, zero, amountless, expired and unrepresentable amounts are rejected before fetching quotes.

The immutable plan holds the original invoice and each mint's exact share and expected principal. MPP uses balance-weighted largest-remainder allocation with full-width integer arithmetic and stable tie-breaking. Zero shares are removed; one remaining payer uses an ordinary full-payment request. A matching aggregate cannot conceal individual mismatches such as 7/3 quoted for a requested 6/4 split.

Full payments use CashuSwift's typed quote API. Its typed request cannot yet encode MPP, while its generic response decoder truncates fractional numbers and replaces the method echo. A small quote-only HTTP adapter therefore sends the existing generic MPP request shape and decodes the original response into the typed BOLT11 quote. This preserves invoice echoes and rejects malformed numeric fields before validation.

The loader validates each quote's principal, unit, optional invoice echo, state, expiry and fee arithmetic. Every participating mint must fund its own principal, Lightning reserve and proof input fees before the view enables payment.

A generation check prevents obsolete successes or errors from publishing after invoice, selection or allocation changes. The view also invalidates ready quotes when balances or capabilities change and when it disappears. Payment counts and totals use only the current plan's active legs.

Proof reservation, execution and pending-payment recovery retain their existing owners. This mitigation requires no dependency or storage-schema change.

## Regression coverage

`BOLT11MeltTests` covers integer rounding boundaries, all BOLT11 amount multipliers, uppercase invoices, invalid/expired/overflowing inputs, deterministic allocation, zero legs, per-share mismatches, full and partial HTTP request bodies, malformed responses, per-mint fee coverage, and obsolete asynchronous responses. Hosted SwiftUI checks exercise full fractional-sat payments, whole-sat MPP, unsupported fractional splits, and balance changes after readiness.

Tests use signed synthetic invoices, stubbed HTTP responses and in-memory proofs. They verify quote negotiation does not reserve proofs, create payment events or consume derivation counters.

## Protocol references

- [CDK wallet validation, revision 5cca094](https://github.com/cashubtc/cdk/blob/5cca0943cf8d05f50b1c73af3aee2c430d70f60d/crates/cdk/src/wallet/melt/bolt11.rs#L51-L70)
- [CDK LND quote rounding](https://github.com/cashubtc/cdk/blob/5cca0943cf8d05f50b1c73af3aee2c430d70f60d/crates/cdk-lnd/src/lib.rs#L1050-L1085)
- [Nutshell 0.21.0 full-payment rounding](https://github.com/cashubtc/nutshell/blob/0.21.0/cashu/lightning/lndrest.py#L520-L540)
- [Nutshell MPP validation, revision c32cb38](https://github.com/cashubtc/nutshell/blob/c32cb388af7b5fffa2a9e310711f144595a31e15/cashu/mint/ledger.py#L1003-L1020)
- [NUT-15 payment coordination](https://github.com/cashubtc/nuts/blob/main/15.md)
