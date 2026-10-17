# Pre-launch fixes applied

## 🔴 Security (blocking)

**1. Email enumeration on login — `lib/auth_screen.dart`**
Removed the `email_is_registered` RPC pre-check that told the user outright
whether an email was registered before attempting sign-in. Login now goes
straight to `signInWithPassword`, and the "invalid login credentials" error
is shown as a single generic message ("Incorrect email or password.") that
doesn't reveal whether the email exists.

**2. Password-reset PII leak — `lib/auth_screen.dart`**
The old flow called `lookup_account_for_reset` and displayed the matching
account's username + profile photo on screen *before* sending anything —
letting anyone harvest (email → username/photo) pairs with no auth at all.
Replaced with a single-step flow: enter email, tap send, always see the same
generic confirmation ("If that email is registered, a reset link has been
sent to it") regardless of outcome. The RPC call is gone entirely — you can
drop `lookup_account_for_reset` and `email_is_registered` from the DB if
nothing else calls them (grep first — a search of this codebase turned up no
other callers).

## 🟡 Code quality

**3. Silent failure — `lib/notifications/notification_page.dart`**
Empty `catch (_) {}` around per-notification timestamp parsing now logs via
`debugPrint` so a malformed row doesn't fail completely silently. Behavior
(skip that row) is unchanged.

**4. Missing `mounted` guard — `lib/profile/edit_profile_page.dart`**
`_loadCurrentUserData()` called `setState` after an `await` with no
`mounted` check — could throw if the user backs out of Edit Profile before
the fetch resolves. Added guards before both `setState` calls in that
method.

**5. Missing `mounted` guards — `lib/auth_screen.dart` (signup validation)**
The empty-username and password-mismatch checks in the sign-up flow called
`Navigator.pop`/`ScaffoldMessenger` without a `mounted` check. Low risk in
practice (no `await` happens before them), but made consistent with the
rest of the file.

**6. Duplicate-row race in gift inventory — new migration
`supabase/migrations/2026_gift_inventory_upsert_fix.sql`**
`send_gift_to_user` and `claim_random_gift_from_ad` (in
`2026_chat_redesign.sql`) used an `UPDATE` filtered on `"expiresAt" IS NULL`
followed by a conditional `INSERT` on `NOT FOUND`. If a user already held an
*expired* row for that `(ownerUid, giftId)` pair, the `UPDATE` would never
match it, and a second live row got inserted instead of updating one — and
the two-step check-then-act wasn't even atomic under concurrent calls. The
new migration:
- merges any duplicate "permanent" rows that already exist in your DB,
- adds a partial unique index enforcing at most one `expiresAt IS NULL` row
  per `(ownerUid, giftId)`,
- replaces both RPCs with a single atomic `INSERT ... ON CONFLICT ... DO
  UPDATE`.

Run this migration after `2026_chat_redesign.sql`. It's idempotent — safe to
re-run.

## 7. `send_gift()` audit (RPC pasted separately, not in this zip)

Checked against the same duplicate-row question raised in #6 — it doesn't
apply here: `send_gift()` never inserts into `gift_inventory` for the
recipient, only deducts from the sender's rows (with proper `FOR UPDATE`
row locking, which is actually more robust than what the chat RPCs had).
The `select "userName" into v_recipient` also looked wrong at first glance
(`v_recipient` is `uuid`) but checked out — `posts."userName"` is a legacy
column name that now holds the owner's UID (`kPostOwnerUidField = 'userName'`
in `models.dart` confirms this), so no bug there.

One real gap turned up, fixed in the new migration
`supabase/migrations/2026_search_path_and_self_gift_fix.sql`:

- **`search_path` wasn't pinned** on any of the 6 `SECURITY DEFINER`
  functions from `2026_chat_redesign.sql`, or on `send_gift()` itself
  (`send_gift_to_user()` / `claim_random_gift_from_ad()` got it directly in
  `2026_gift_inventory_upsert_fix.sql` since that migration already
  redefines them). All of them now pin `SET search_path TO 'public'`,
  matching standard `SECURITY DEFINER` hardening practice — no other logic
  changed in any of these functions.

**Self-gifting is intentional, not a bug — reverted.** An earlier pass of
this fix also blocked gifting your own post (a comment elsewhere in the
code implied that used to be blocked), and hid the Gift button on your own
posts client-side. That was undone on request — self-gifting is a
user-requested feature. `send_gift()`'s logic is untouched beyond the
`search_path` pin; the Gift button shows on every post again, same as
before.

## Migration run order

1. `2026_chat_redesign.sql` (already existed)
2. `2026_gift_inventory_upsert_fix.sql`
3. `2026_search_path_and_self_gift_fix.sql`

All three are idempotent — safe to re-run if you're not sure what's already
applied.
