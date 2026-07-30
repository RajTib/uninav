# UniNav — Security

> ## ⚠ Status: rules written, never deployed, never tested
>
> **The app has no backend, no authentication and no network access.** It reads bundled assets and writes to local key-value storage. The current attack surface is a device the user already controls.
>
> **What exists:** complete Firestore and Storage rules at `app/firebase/firestore.rules` and `app/firebase/storage.rules`, kept in-repo from the start so the security model evolves alongside the data model instead of being retrofitted. They have **never been deployed and never been run against the emulator suite.** Treat them as a reviewed design, not as tested code.
>
> **What this means practically:**
>
> | Concern | Current reality |
> |---|---|
> | Authentication | None — no accounts exist |
> | Authorisation | Not applicable — nothing is writable remotely |
> | Data at rest | Bundled assets, world-readable by design |
> | User data | `shared_preferences`, device-local, not encrypted |
> | Secrets | **None in the repo** — verified; there is no Firebase config to leak |
> | Network | The app makes no network calls |
>
> **Before any deployment:** the rules must be run against the Firebase emulator suite with a test matrix covering each role and each collection. Deploying untested rules is how privilege-escalation bugs ship.
>
> See [14-roadmap.md](14-roadmap.md) and [15-known-issues.md](15-known-issues.md).

Related: [Data model](03-data-model.md) · [Community mapping](06-community-mapping.md) · [Admin dashboard](07-admin-dashboard.md)

---

## Principles
1. Roles live in `roles/{uid}` (admin-writable only) — profile writes can never escalate privilege.
2. Published map data is public-read; ALL writes to map/versions/roles go through privileged actors (moderator client now, Cloud Functions later). Client apps never write map data directly.
3. Everything user-writable is validated in rules (shape, size, ownership, immutable fields).

## Authentication
- Firebase Auth: anonymous (browse) → Google / email+password (contribute; email verified required for contributions).
- Account linking: anonymous → signed-in preserves local data.
- No custom token handling; sessions are Firebase-managed.

## Firestore rules sketch (full file ships with the repo)
```
function isSignedIn()  { return request.auth != null; }
function role()        { return get(/databases/$(db)/documents/roles/$(request.auth.uid)).data.role; }
function isModFor(c)   { return role() in ['admin','moderator']
                          && c in get(...roles...).data.campusIds; }

campuses, buildings, versions, announcements:  read: true;  write: role() == 'admin' || isModFor(campusId)
roles:          read: request.auth.uid == uid; write: role() == 'admin'
users/{uid}:    read/write: owner; reputation & contributionCount immutable to owner
users/{uid}/saved, routeHistory: owner only
contributions:  create: signedIn && emailVerified && author == uid && status == 'pending'
                        && payload size < 20KB && rateLimitOk()
                read:   author || isModFor(campusId)
                update: only moderator, only status/review fields (author may cancel pending)
feedback:       create: signedIn; read: staff
auditLogs:      write: staff; read: admin
```
`rateLimitOk()`: contribution doc ids embed `{uid}_{yyyymmdd}_{n}` with `n < 10` enforced by rule pattern + a daily counter doc transactionally incremented; this is best-effort until Functions enforce it server-side (accepted, documented gap).

## Storage rules
- `bundles/**`, `plans/**`: public read, staff write.
- `contrib/{contributionId}/**`: write by contribution author while pending, ≤ 5 MB, image content-type; read staff-only until the contribution is approved (unmoderated images must never be publicly served).

## App-side
- No secrets in the repo: Firebase config via `--dart-define`/flavors; App Check enabled to cut abusive non-app traffic.
- Input sanitization on contribution text (length caps, control-char strip); photos re-encoded client-side (EXIF/GPS stripped — contributor privacy).
- Least-privilege UI: role-gated routes are also rules-gated; UI gating is UX, rules are the boundary.

## Threats reviewed
Spam floods (rate limit + reputation + shadow throttle), privilege escalation (roles isolation), poisoned map data (pre-moderation + validation + versioned rollback), quota-burn attack via bundle re-downloads (App Check + immutable cached bundles), scraping (accepted: map data is public by design).
