# UniNav — Feature Backlog

> **Status: idea register, not a plan.** Nothing here is committed. The committed work is in [14-roadmap.md](14-roadmap.md); anything not in a roadmap phase is unscheduled by definition.
>
> Kept because knowing what was *considered and deferred* is as useful as knowing what was chosen — it prevents re-litigating settled decisions and shows the shape of the problem space.

Related: [Roadmap](14-roadmap.md) · [SRS](01-srs.md) · [Navigation runtime](18-navigation-runtime.md)

---

## Delivered

Already shipped, with the doc that describes each:

| Feature | Doc |
|---|---|
| Room search by number, name and alias | [09](09-search.md) |
| Fuzzy + prefix search with ranking | [09](09-search.md) |
| Shortest path via A* | [04](04-routing-engine.md) |
| Multi-floor transitions | [04](04-routing-engine.md) |
| Step-free (no-stairs) routing | [04](04-routing-engine.md), [10](10-accessibility.md) |
| Prefer-lift mode | [04](04-routing-engine.md) |
| Floor viewer: pan, zoom, tap-to-select | [05](05-map-representation.md) |
| Turn-by-turn step list | [04](04-routing-engine.md) |
| Offline operation | [02 §7](02-architecture.md) |
| Building browser incl. unmapped buildings | [08](08-ui-screens.md) |
| Favourites and recent searches | [08](08-ui-screens.md) |
| Report a problem (offline outbox) | [08](08-ui-screens.md) |
| Anonymous use — there is no account | — |
| Washroom POIs and **nearest-washroom routing** | [04 §3.4](04-routing-engine.md) |
| Deep links: `/map?room=`, `/plan?dest=&from=` | [08](08-ui-screens.md) |
| Dark mode | [05 §7](05-map-representation.md) |
| Bundle versioning field in the schema | [03](03-data-model.md) |

---

## Next (Phase 1)

Committed. See [14-roadmap.md](14-roadmap.md).

- Complete SJT floors 5, 4, 3, 2, 1, Ground
- Graph validation in the generator actually in use
- An `entrance` node and entrance-based default start
- **Simulated navigation blob** ([18](18-navigation-runtime.md))
- Travelled-versus-remaining route styling

---

## Deferred — designed, unscheduled

Each has a design document already written. They are deferred on sequencing, not on merit.

| Feature | Design | Blocked on |
|---|---|---|
| Community contributions (add / move / rename) | [06](06-community-mapping.md) | A map worth correcting; a backend |
| Moderation queue and reputation | [06](06-community-mapping.md) | Contributions |
| Admin floor editor | [07](07-admin-dashboard.md) | The browser tracer suffices at current scale |
| Bundle import/export with dry-run diff | [07](07-admin-dashboard.md) | Admin tooling |
| Zero-result search analytics — the mapping-gap detector | [07](07-admin-dashboard.md) | Any telemetry at all |
| Sign-in and cross-device sync | [12](12-security.md) | Backend |
| Multi-campus in one install | [03](03-data-model.md) | Remote bundle tier |
| Per-campus announcements | [03](03-data-model.md) | Backend |
| Raster plan underlay rendering | [05 §8](05-map-representation.md) | Remote data source + disk cache |
| Voice guidance (TTS) | [10](10-accessibility.md) | — |
| Multi-language (i18n) | [04 §6](04-routing-engine.md) | — |
| Saved locations ("my hostel room") | — | — |
| Share a route as a link or QR | — | Deep links already exist; needs a share sheet |

---

## Candidate features (unscheduled)

Grouped by what they need, which is more useful than a flat list.

**Needs only map data**

Gender-filtered washrooms · water cooler / printer / ATM / vending POI layers · departments directory · faculty cabin search · building open-hours with closed-route warnings · emergency exit route mode · first-aid and AED locator · cycle stands · parking zones · hostel blocks · club-room directory

**Needs a backend**

Elevator outage reports (community, time-boxed) · temporary closures with reroute · lost & found board · food court menus and hours · shuttle stop info · contribution leaderboards · "what's new in your campus map" · TV/kiosk mode for lobbies

**Needs UI work only**

Route preview scrubber · walking-time and step estimates · route history insights · home-screen widgets · high-contrast theme · campus tour mode with curated waypoints

**Needs integration**

Timetable import (ICS or photo) → "navigate to next class" · LMS/ERP deep links · printer queue status · exam-hall finder by seat number

**Needs positioning** — all blocked on [18 §5](18-navigation-runtime.md)

QR checkpoints · BLE beacons · Wi-Fi RTT · dead reckoning · AR wayfinding overlay · crowd density heatmaps · social meetup pins · smart-glasses directions · haptic-belt navigation for blind users

---

## Research ideas

Genuinely speculative. Listed because a few are legitimately paper-shaped.

| Idea | Note |
|---|---|
| **Graph-constrained dead reckoning** | **Highest research value.** UniNav already has the corridor graph; snapping PDR output to graph edges should bound drift measurably versus unconstrained PDR |
| Camera relocalisation — photo of a corridor → position | Well-studied outdoors; indoor corridors are visually repetitive, which is exactly what makes it hard |
| Auto-OCR of door nameplates → room suggestions | Would cut mapping cost, the project's actual bottleneck |
| Photogrammetry from student videos to generate plans | Same motivation, much harder |
| LLM concierge — "where do I pay hostel fees?" → office + route | Needs a services directory more than it needs an LLM |
| Occupancy prediction | Needs longitudinal data nobody is collecting |
| Federation between campuses, OSM-style | Interesting only once several campuses exist |
| Open data export under an ODbL-style licence | A governance decision, not an engineering one |
| Digital-twin API for facilities teams | The most plausible route to institutional funding |

---

## Prioritisation rules

1. **Nothing from "candidate" starts until Phase 1 is complete for one full building.** A thin map with many features is worse than a complete map with few.
2. **Nothing hardware-dependent before QR checkpoints prove the localisation UX.** Beacons and Wi-Fi RTT are infrastructure commitments; QR costs a printout.
3. **Nothing needing a backend before there is content worth backing.** Firebase adds capability the project cannot yet use.
4. **A feature that cannot be maintained by one person does not ship**, however good the demo.
