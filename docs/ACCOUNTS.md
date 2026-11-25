# Shared accounts: Vercel + Neon

**Current installer: Build 29.** See [Build 29 delivery and unread behavior](BUILD29.md). The numbered build sections below document how the app evolved; later sections supersede earlier behavior. Current layout uses the top search bar, text map tabs and right-side controls. Owner controls are in the profile/dashboard.

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
- New regular and owner sessions last 30 days. Owner sessions issued before Build 19 retain their earlier one-hour expiry until you sign in again. Stay logged in saves the opaque session token in the iPhone Keychain, not passwords. Sign out clears it. iOS Keychain items may survive uninstalling the app.
- Foreground account status and inbox are checked every 30 seconds. Saved logins retain their last server-verified profile during network failures, including offline relaunch. Reconnection retries account checks. A definitive 401/403 response clears the session. Users upgrading from Build 14 should connect once to save the offline profile. Owner actions and inbox updates always require the server. Offline devices cannot learn about account revocation until they reconnect.
- Owner lists show profiles from all devices, in pages of 40. Password hashes are never returned.
- Delete permanently deletes the online account and cascades all sessions and messages, blocking access from every device on its next server request. It does not erase an offline app install, local route history, or remotely stop an already-running simulated location session. Modified clients are outside this UI's control.
- Owner messages appear in each recipient's private in-app inbox (latest 50), not as background or lock-screen push notifications. Push delivery requires APNs configuration and is not implemented.
- Login and API requests are rate limited. Database-side cascading deletion revokes all target sessions. Queries are parameterized.

## Verification
From `backend/vercel`, run `npm ci` and `npm test`. The tests use embedded PostgreSQL and cover two independent sessions, incorrect passwords, duplicate sign-ups, owner-email reservation, role escalation attempts, owner-only lists/deletion/messages, recipient-only delivery, session revocation and message cleanup on deletion, and sign-out.

The live production smoke test uses a disposable account, verifies owner visibility, a second sign-in, message delivery and owner-only deletion, then deletes only the disposable account and logs out the test owner session. The iPhone app still needs an installed-device UI check after signing the new IPA. Test accounts and their messages must not be left in production.

Availability depends on the Vercel and Neon plans and quotas. Database compute may sleep and wake on demand; this setup does not require manually resuming a Supabase project. Check the providers' current quotas before a large public launch.

## Build 15 checks

Run `xcrun swiftc -parse-as-library Waypoint/Models/SelectedCoordinate.swift Waypoint/Services/AccountStore.swift tests/AccountOfflineTests.swift -o /tmp/roam-account-tests && /tmp/roam-account-tests` on a Mac. This uses a simulated network transport and unique temporary Keychain entries. It verifies offline login retention, server failure, reconnection, server revocation, saved offline relaunch and explicit sign-out. Build 15 also adds an in-place collapsed route panel, saved map/pin styles, a 3D following camera and on-demand Look Around imagery where available. Device UI and background behavior require iPhone verification.

## Build 16 referral form and update screen

New sign-ups select TikTok, Instagram, LinkedIn or Resume and supply a required social handle (LinkedIn accepts its profile slug). Resume requests a TikTok, Instagram or LinkedIn handle because resumes have no platform-specific @. The owner sees the source and handle. Existing clients that do not send either referral key remain supported; new clients send both and the server validates the choice and handle. Existing profiles and cached logins decode without these fields. The update reminder appears at launch and on return from background, with links and a Continue button; transient inactive states such as Control Center do not reset it. Follow status is not verified. Build 16 includes Build 15 fixes.

## Build 18 announcements and password visibility

Owner dashboard → Send notif opens a composer with a 2,000-character limit and a confirmation showing the draft. On confirmation, one database statement writes the broadcast and individual inbox messages for all currently registered accounts. The server checks owner permissions. A stable request UUID prevents duplicate sends when retrying after a lost response; editing the draft creates a new request. Success reports the current recipient count. No lock-screen/APNs push is sent. Future accounts do not receive past broadcasts. Broadcast records retain the announcement body for deduplication even after recipient deletion; individual inbox messages still cascade on account deletion. The owner can also continue to send individual messages.

All password entries now have accessible Show/Hide buttons. Passwords start hidden each time the sign-in view is created and are cleared after submission. Existing credential storage remains unchanged. Backend tests cover broadcast access control, length validation, per-recipient delivery, retries and conflicting request IDs. No announcement has been sent to real users as part of development.

## Build 19 unread alerts and session persistence

New messages appear as an in-app banner after the launch reminder closes, with a red profile badge until the inbox is read. Dismissing the banner retains unread status. Read IDs are stored per account on the current device; read state does not sync between devices. Cached messages can display offline. There are still no background lock-screen pushes. Keychain sessions are now updated atomically instead of deleted/re-added on refresh. New owner sessions last 30 days; an expired prior owner session needs one fresh login. Stay logged in must be enabled to restore after termination. Existing Keychain entries may be unavailable after signing identity/bundle changes; on-device verification remains required.

Map controls now use a separate scrollable panel and pause following-camera updates while open. Destination/selected symbols are red, start flags blue, active symbols cyan, uncovered routes yellow and covered road segments green. Coverage is projected onto the nearest road segment and throttled to two updates per second; intersecting/looped routes can make nearest-segment coverage ambiguous. Pins use layered symbols, gradients, glow, pulse and camera-pitch-responsive perspective; these are stylized extrusions, not full 3D vehicle models.

## Build 20 activity, photos and optional shared location

Sign-up offers a profile photo, resized/cropped to a 128px JPEG before upload, and an off-by-default location-sharing toggle. System PhotosPicker only provides the chosen photo. The owner sees profile photos with existing names/emails/social handles. Profiles use 40-row pages to keep image payloads within hosting response limits. Photo size/type and coordinates are validated on the server.

Foreground heartbeats run approximately every 15 seconds while signed in. Last-active uses the server timestamp. A green dot means the latest heartbeat marked the app active within 45 seconds; it is an estimate, not proof the user is physically using the phone. Background/sign-out attempts mark the account inactive. Abrupt closure/network loss ages out naturally. Older app versions do not report presence and show no last-active data until updated.

Location sharing is optional and separately disclosed at signup and in the profile. With consent enabled, a foreground heartbeat includes the app's simulated coordinate and Spoofing flag, or the location reported by Core Location when there is no app simulation. The system asks for When In Use permission before collecting device location. Permission denial can leave reported-location unavailable. GPS may be approximate, stale or already simulated by another tool, so the UI calls it device-reported rather than verified real location. The tracker stops when backgrounded or sharing is off; no background location collection was added for owner tracking.

The owner map and member list refresh about every 15 seconds while visible. Each pin includes a location-report timestamp and can show a last-known location after the user goes offline. Location updates require internet; airplane mode cannot stream reports. These are periodically refreshed pins, not 0.1-second remote tracking.

Turning sharing off stops client collection/uploads immediately, including offline. The opt-out is queued locally until the next connection; the server's existing last-known coordinate cannot be erased while offline. Once connected, profile-settings clears stored coordinates and status. A late heartbeat checks current server consent and cannot repopulate location after opt-out. The database stores only the latest coordinate, not route history. Account deletion cascades profile/location records. Users who don't opt in show Location not shared. Presence still reports last-active for signed-in users, as disclosed in signup.

Validation covers default-off location privacy, opt-in reports, spoofing/non-spoofing flags, invalid coordinates, background/inactive status, opt-out clearing and stale heartbeat protection, owner-only lists, user-only self updates, photo type rejection and cross-account ID spoof attempts. Installed-device photo selection, permission prompts, map pin refresh and foreground/background transitions remain to be verified on iPhone.

## Build 21 Community map

Community map is available from the main map's Community menu and the account panel. Non-owner users must separately opt in to join and view it. Declining dismisses the screen; the consent prompt appears again on the next entry. Declining does not disable the core app. The prompt discloses audience (other enrolled signed-in users and the owner), username/photo/spoofing status, device-reported versus simulated coordinates, approximate location, foreground refresh, last-pin persistence, and the owner's ability to view without joining. No chat or dating system is included.

Private sharing with the owner remains independent. Existing private-sharing consent never automatically enrolls anyone in Community map. Community-only users' exact coordinates are masked in the private owner-list response. Community-list returns rounded two-decimal coordinates, username, photo and spoofing/activity timestamps; it does not return email or social handles. Approximation is roughly kilometre scale and does not guarantee anonymity. Pins expire from the community response after ten minutes without a location report. Authenticated non-enrolled users and blocked users cannot fetch community data; owners may fetch it without sharing their own location.

Leaving stops local community access and sharing immediately. If offline, clearing the public server pin waits for reconnection or ten-minute expiry. Leaving does not turn off separately opted-in private owner sharing. Queued local opt-out persists across relaunch. The owner can remove/block a member from Community map and later restore eligibility. Removal clears community enrollment, removes their public pin and blocks rejoining. Restoring eligibility leaves enrollment off until the user explicitly joins again. It does not alter their private owner-sharing setting. Late heartbeats cannot repopulate either location channel without current server consent.

Tests cover default access denial, owner exemption, separate consent, rounded coordinates, absent private fields, exact-coordinate masking for community-only accounts, owner-only removal, rejoin blocking, restore-without-enrollment, leave/stale heartbeat protection and offline local leave. Community UI, permission prompts and map interactions still need installed-iPhone validation.

## Build 22 unified Community map

Community map now toggles other members' avatar pins on the SAME MapSpoofView instance. It does not navigate to a second map, rebuild the route controller, change the selected spoof coordinate, or reset the camera. The original search, custom pins, route preview/playback, pause/restore, style choices and Look Around controls remain available. Avatar taps show a small profile card above the same map and ignore the map-tap-to-select action near that avatar. A Hide people action removes only community visuals; the separate Leave control in the profile disables community sharing.

The main Community menu toggles the mode. The account-panel Community entry dismisses that panel and opens the same main-map mode. Unenrolled users first see the existing consent screen; accepting returns to the original map with community pins enabled. Owners remain exempt from joining, and removal/eligibility and approximate-location checks are unchanged. Polling runs every 15 seconds only while Community mode is visible and the app is active. The private owner activity map remains separate from the shared community view. Map/avatar gestures and ongoing driving while switching modes still require installed-iPhone verification.

## Build 25 last-known owner pins and username labels

The earlier Community map response dropped every pin ten minutes after its last coordinate report. A new, separately disclosed community_keep_for_owner flag lets the owner retain the latest approximate pin after closure or sign-out until Community map enrollment is disabled, the owner removes the user, or the account is deleted. This stores/displays the existing last report; it does not collect new background GPS or bypass iOS/sign-out. It is not proof of the user's present physical whereabouts. Regular community members still get only reports from the last ten minutes.

Existing members keep the prior ten-minute limit for the owner until they review and accept the updated Community sharing notice. New Build 25 joins include the new disclosure and consent flag. Older clients do not set this flag. Restoring eligibility after removal does not restore this consent. The UI offers Review last-known sharing to existing members, and the Community button opens that review when needed.

Custom username labels now appear directly under avatars on the integrated Community map and private owner activity map; automatic MapKit titles are hidden to avoid duplicates. Inactive community pins show Last known, and tapping displays the last-report time. Tests cover legacy consent expiry, owner-only retention, ordinary-member expiry, and sign-out revoking the session without deleting the consented last-known pin.

## Destination check-ins (Build 30)

Before starting a new fixed spoof or route, users submit their actual destination as text. The form explains that this is stored privately for the owner, and can be cancelled without starting the spoof. An internet connection is required to submit. These reports are user-entered, unverified information, not live GPS or an emergency service. They never appear on Community maps.

The owner receives new reports through the existing in-app inbox and unread badge while online. Open an inbox report’s user profile, or tap **View profile & destination reports** in the owner account list, to see that user’s report history. No background push delivery is provided. Account deletion removes the user’s reports.
