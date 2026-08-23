# Contributing

The most valuable contribution to this repo is **verification against a tenant with real
consumption**. The endpoints were confirmed working, but the test tenant reported zero consumed
credits, so field behaviour under load is still unknown.

## Report a verification result

Use the **Verification result** issue template. The specific unknowns:
- Are `consumed` values populated on resource rows when agents are actively used?
- Is `metadata.NonBillableQuantity` ever non-zero, and what drives it?
- Do `payGo.entitled` / `payGo.consumed` populate once capacity is exceeded?
- Does `capacity.status` change from `WithinCapacity`, and to what?
- How far behind real time is `lastUpdatedOn` in practice?
- Does paging behave beyond `pageSize=5000`?
- What does `includeFields=users` add to the response?

**Redact your tenant ID, environment IDs, resource IDs and agent names before posting.** Shapes and
magnitudes are what matter, not identifiers.

## Report an endpoint change

If a call starts returning `404`, follow [docs/devtools-capture.md](docs/devtools-capture.md) and
open an issue with the old and new paths, method, audience and response shape.

## Pull requests

1. One concern per PR.
2. Scripts must stay **read-only** - no `POST`, `PATCH` or `DELETE` against a tenant.
3. Parse defensively. These are private APIs; assume properties may be missing or renamed.
4. Never commit a tenant ID, environment ID, bearer token, webhook URL or captured response
   containing real identifiers.
5. If you change documented behaviour, update `docs/api-reference.md` and state whether the change
   was verified live or inferred.

## The verified/inferred distinction

This repo deliberately separates what was confirmed against a live tenant from what was assumed,
including negative findings. Please preserve that when contributing - an unverified claim presented
as fact is worse than no claim, because the next person builds on it.

## Code of conduct

Be constructive and assume good faith.
