# Build 26: Community pins after consent

Changes:
- Community consent success wakes the heartbeat loop immediately, rather than waiting for its 15-second timer.
- A fresh device location triggers a consent-checked report immediately, throttled to five seconds. If the user's first pin is missing, the client reloads community data after that report. Active simulated positions are published by the normal heartbeat.
- Account status/presence responses capture a profile revision. Responses from before a sharing change cannot overwrite newly accepted or revoked consent. A regression test delays the old account response and proves acceptance remains enabled.
- Location permission, GPS availability, location upload errors, community fetch errors, loading state and pin count are visible. Consent alone does not create coordinates; an online device fix or active app simulation is needed. Owner accounts can view others without sharing a pin themselves.
- Show pins explicitly fits all returned coordinates. The first available set auto-frames only if the user hasn't selected a point, begun route planning or enabled the driving camera. These guards prevent a late network response from interrupting a route or search.

Validation:
- Release compilation passed.
- Client tests passed for the consent-refresh race, offline state, explicit leave, saved login and server session revocation.
- A live smoke test used two disposable QA accounts: signup, explicit community consent, upload of synthetic CN Tower coordinates, and retrieval of that rounded pin by the other account. The QA accounts and pins were deleted in cleanup; existing users' details were not printed.
- Installed-iPhone location permissions, GPS acquisition and camera framing remain to be verified on device. No backend change was needed for this build.
