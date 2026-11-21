# Shared accounts: Vercel + Neon

Roam Control uses a dedicated `/api/roam-accounts` service on the existing Overline Vercel project. It shares hosting and the Neon database, but uses separate `roam_` tables, session tokens and owner password hashes. Overline accounts and credentials are unchanged. Supabase is not required. No process on the developer's laptop is needed for account access.

## Running deployment
The app's `AccountServerURL` is `https://overline-orcin.vercel.app/api/roam-accounts`. No API secret is shipped in the app. The corresponding source is `backend/vercel/api/roam-accounts.mjs`, also copied into the existing Overline hosting checkout's `api` directory. Future deployments of that hosting project must preserve this endpoint.

Server environment variables:
- `DATABASE_URL`: existing private Neon connection string, server only.
- `ROAM_OWNER_EMAIL`: owner login email.
- `ROAM_OWNER_HASHES`: JSON array of three independently salted scrypt password hashes (`salt`, `hash`); never plaintext passwords. Separate from Overline's settings.

The endpoint creates its namespaced schema on first database request. `backend/accounts.sql` contains the equivalent schema. It never modifies Overline tables. A new deployment elsewhere requires PostgreSQL, these environment variables, and an updated AccountServerURL in the IPA.

## Account behavior
- Sign-up collects username, email, password and optional TikTok/Instagram handles. The follow notice is displayed before submission; follows are not automatically verified.
- Email/password registration is immediate. This version does not verify email ownership and does not provide email password reset. The owner email is reserved and cannot be registered publicly.
- Owner sign-in uses the Owner sign-in switch and all three owner passwords in order. Server verification is required; client flags cannot grant ownership.
- Regular sessions last 30 days; owner sessions last one hour. Stay logged in saves the opaque session token in the iPhone Keychain, not passwords. Sign out clears it. iOS Keychain items may survive uninstalling the app.
- Foreground account status and inbox are checked every 30 seconds. Account checks require connectivity. Network failure blocks the account gate until a later successful sign-in/check.
- Owner lists show profiles from all devices, in pages of 500. Password hashes are never returned.
- Delete permanently deletes the online account and cascades all sessions and messages, blocking access from every device on its next server request. It does not erase an offline app install, local route history, or remotely stop an already-running simulated location session. Modified clients are outside this UI's control.
- Owner messages appear in each recipient's private in-app inbox (latest 50), not as background or lock-screen push notifications. Push delivery requires APNs configuration and is not implemented.
- Login and API requests are rate limited. Database-side cascading deletion revokes all target sessions. Queries are parameterized.

## Verification
From `backend/vercel`, run `npm ci` and `npm test`. The tests use embedded PostgreSQL and cover two independent sessions, incorrect passwords, duplicate sign-ups, owner-email reservation, role escalation attempts, owner-only lists/deletion/messages, recipient-only delivery, session revocation and message cleanup on deletion, and sign-out.

The live production smoke test uses a disposable account, verifies owner visibility, a second sign-in, message delivery and owner-only deletion, then deletes only the disposable account and logs out the test owner session. The iPhone app still needs an installed-device UI check after signing the new IPA. Test accounts and their messages must not be left in production.

Availability depends on the Vercel and Neon plans and quotas. Database compute may sleep and wake on demand; this setup does not require manually resuming a Supabase project. Check the providers' current quotas before a large public launch.
