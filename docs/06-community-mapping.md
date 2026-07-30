# UniNav — Community Mapping System

> ## ⚠ Status: DESIGN ONLY — not implemented
>
> **No contribution, moderation, versioning or reputation code exists.** There is no backend, no auth, and no `contributions` collection. Nothing in this document is running.
>
> **What does exist** is the seed of it: a report-a-problem bottom sheet reachable from any room card, a failed route, or an unmapped building. Reports queue in a local **offline outbox** (`FeedbackOutboxNotifier`) with a `markDrained` hook waiting for a future sync worker. The user is told their report succeeded, because from their point of view it did — network is the app's problem, not theirs.
>
> **Why deferred:** moderation is meaningless before there is a map worth correcting. The current map is two floors of one building ([15-known-issues.md](15-known-issues.md)). Building a contribution pipeline now would be infrastructure for content that does not yet exist.
>
> **Why kept:** this design shapes decisions already made — bundle immutability, versioned publishing, the separation of `roles/` from `users/`, and payloads that mirror bundle shapes so approval is a mechanical merge. Discarding it would lose the reasoning behind those.
>
> See [14-roadmap.md](14-roadmap.md) for sequencing.

Related: [Data model](03-data-model.md) · [Security](12-security.md) · [Admin dashboard](07-admin-dashboard.md) · [Mapping guide](16-mapping-guide.md)

---

## 1. Model: propose → moderate → publish (never direct edit)

Users never mutate map data. They create **Contribution** documents (03-data-model.md) whose payloads mirror bundle shapes. Moderators apply approved contributions, which produces a new immutable **MapVersion**. This is OSM's lesson applied with a stricter gate: on a young map, one bad edit visibly breaks navigation, so pre-moderation beats post-moderation until trust exists.

Contribution types: `addRoom, moveRoom, renameRoom, editRoomTags, addEdge, removeEdge, addPoi, reportIssue, photo`.

## 2. Approval workflow

```
draft(client) → pending → approved → applied (appliedInVersion set)
                   ↘ rejected(reason)      ↘ superseded (newer contribution wins)
```

- Moderators are scoped per campus (`roles/{uid}.campusIds`).
- Approve = validate payload → merge into working copy of bundle → run graph validation (connectivity, dangling refs) → publish new version → mark contribution applied → +reputation. Batched: a moderator can approve 10 contributions into one version.
- Reject requires a reason (canned + free text); author is notified.
- Pre-Cloud-Functions this merge runs in the moderator's (admin app) client inside a transaction on the building doc; moving it server-side is a Functions milestone, changing no data contracts.

## 3. Versioning & rollback

Every publish = new bundle file + `versions/{n}` doc with `sourceContributionIds`. Rollback = pointer flip of `publishedVersion` (old bundles are never deleted). Because bundles are immutable, clients can't observe a half-published state.

## 4. Conflict resolution

Conflicts are detected at approval time, not submission time (users can't see each other's pending edits):

- Contribution stores `baseVersion` (version the user was viewing). If the target object changed since `baseVersion`, the moderator UI shows a three-way view (base / current / proposed).
- Same-target pending contributions are grouped; approving one marks contradicting ones `superseded` (authors notified, no reputation loss).
- Geometric sanity checks: proposed room polygon must lie within floor bounds and not overlap an existing room > 30% unless the type is a correction of that room.

## 5. Reputation & trust

```
+2 approved edit   +5 approved new room/edge   +1 accepted issue report
-1 rejected (spam reason: -5)
```
Levels: 0 New → 20 Contributor → 100 Trusted → moderator (manual grant only).
Trusted users' *minor* edits (rename, tags, POI) can be auto-approved with post-moderation; geometry/graph edits always need review. Reputation is computed by the moderation flow only — never client-writable.

## 6. Spam & abuse prevention

- Contributions require sign-in + verified email; rate limit 10/day (rules-enforced counter + server timestamp checks; hard-enforced in Functions later).
- Photos scanned size/type client-side; served only after approval.
- Duplicate detection: same type+target+similar payload → merged into one review item.
- Shadow throttle for repeat spam-rejected accounts; ban = role flag denying contribution writes.

## 7. Audit

Every state change writes `auditLogs`: `{actorId, action, contributionId?, buildingId, before, after, at}`. Append-only, admin-readable. Answers "who broke floor 3 and when" in one query, and makes moderator abuse detectable — moderators are audited too.
