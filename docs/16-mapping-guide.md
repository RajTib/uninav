# UniNav — Field Mapping Guide

How to turn a real building into a working map. Written for one person with a phone, a notebook, and an hour.

## Before you go

**Calibrate your pace once.** Find a known distance — a corridor tile grid, a basketball court line, anything you can measure — and count how many paces cover 10 m. Divide. Most adults land at 0.70–0.80 m per pace. Write your number at the top of your notes. Everything else depends on it.

Take: notebook, pen, phone (camera for door signs you can't transcribe fast enough).

**Do one floor first.** Not the building — one floor. Finish it end to end, generate the bundle, open it in the app. You'll learn more from that loop than from surveying four floors blind.

## What you're actually recording

The app doesn't need a beautiful floor plan. It needs a **graph**: corridors as lines, rooms hanging off them at measured distances. That's it. Three things per floor:

1. **Corridor shape** — a straight run, an L, a rectangle loop, or a few connected runs.
2. **Distances along each corridor** where something is (a room door, stairs, a lift, a washroom).
3. **Which side** each thing is on as you walk.

## In the building

Pick a starting point — usually the main entrance — and call it distance 0 on your first corridor. Then walk it once, counting paces, stopping at each door:

```
c_main (entrance -> far end)
   0   entrance
   8   L   SJT 101   classroom
   8   R   SJT 102   classroom
  15   R   washroom
  30   R   STAIRS  (call it st_main)
  34   R   LIFT    (call it lift_main)
  45   L   SJT 103   lab, Physics dept
  60   end
```

Rules that save you a second trip:

- **Name stairs and lifts, and use the same name on every floor they serve.** `st_main` on the ground floor and `st_main` on the first floor is what tells the app they're the same staircase. Get this wrong and the app will report floors as unreachable.
- **Note which floors each staircase actually reaches.** Some stop at the 3rd. This matters more than room accuracy.
- **Note whether the lift is genuinely usable** — if it's staff-only or permanently broken, that changes step-free routing for real wheelchair users.
- Round distances to the metre. ±1 m does not affect routing quality.
- If a corridor turns, start a new corridor at the turn and `link` them.
- Don't chase perfection on room polygons — the app draws approximate rectangles for now. Room *position along the corridor* is what matters.

## Typing it up

Copy `app/surveys/SJT.survey` as your template, then fill in what you recorded. The format mirrors your notes almost line for line:

```
building SJT "Silver Jubilee Tower" alias=SJT,Tower

floor f0 level=0 "Ground Floor"
corridor c_main from=0,20 to=60,20
entrance 0 L e_main
room 8 L SJT101 "SJT 101" classroom alias=101
room 8 R SJT102 "SJT 102" classroom alias=102
poi 15 R washroom
stair 30 R st_main
lift 34 R lift_main
room 45 L SJT103 "SJT 103" lab alias=103 tag:dept=Physics
```

`from` and `to` are the corridor's endpoints in metres on that floor. For a first floor, just start at `0,20` and run to `<corridor length>,20` — the exact frame doesn't matter as long as all floors of the building use the same one, so stairs line up vertically.

**L-shaped floor?** Two corridors plus a link:

```
corridor c_main  from=0,20  to=60,20
room 8 L SJT101 "SJT 101" classroom
corridor c_wing  from=60,20 to=60,60
room 12 L SJT120 "SJT 120" classroom
link c_main 60 c_wing 0
```

## Generating the map

```bash
cd app
dart run tool/survey/survey_to_bundle.dart surveys/SJT.survey
flutter run
```

The generator computes every coordinate and edge, connects stairs and lifts across floors, and then runs **the same graph validation the app runs**. It refuses to write a bundle that's broken, and tells you why:

- `room "SJT 305" is not reachable from e_main` — that floor has no working stair/lift link. Usually a typo in a shared stair id.
- `SJT101 at 75 m is outside corridor c_main (0..60 m)` — a distance longer than the corridor.
- `"st_main" appears on only one floor` — you named a staircase but only recorded it once.

Fix, re-run, repeat. When it writes the file, open the app and walk a route you know. If the route looks wrong, the graph is wrong, and the app is telling you something true about your notes.

## Roughly how long it takes

Per floor, for a corridor with ~20 rooms: 20–30 minutes walking, 15 minutes typing. A four-floor block is an afternoon. Your first floor will take twice as long as your second.

## What to skip for now

Room polygons, furniture, exact door widths, anything outdoors, and any block that isn't SJT. Get one building genuinely correct, then decide whether the format survived contact with reality before scaling up.
