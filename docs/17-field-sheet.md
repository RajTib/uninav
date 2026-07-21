# SJT Field Sheet — carry this

## Before you start (2 minutes)

**Pace calibration.** Walk a corridor you can measure (count floor tiles — most are 60 cm or 1 m). Count your paces over 10 m.

```
My paces per 10 m: ______     →  metres per pace = 10 ÷ paces = ______
```

Typical: 13 paces per 10 m ≈ 0.77 m/pace. Use *your* number.

---

## For each floor, write this

```
FLOOR: ____________________  (name as signposted, e.g. "Ground Floor")
LEVEL: ____  (0 = ground, 1 = first, -1 = basement)

CORRIDOR 1  id: c_main     walked from: ________________ towards: ________________
   total length: ______ paces  = ______ m

   PACES   METRES   SIDE   WHAT                          NOTES
   _____   ______   L / R  ____________________________  ______________
   _____   ______   L / R  ____________________________  ______________
   _____   ______   L / R  ____________________________  ______________
   _____   ______   L / R  ____________________________  ______________
   _____   ______   L / R  ____________________________  ______________
   _____   ______   L / R  ____________________________  ______________
   _____   ______   L / R  ____________________________  ______________
   _____   ______   L / R  ____________________________  ______________

CORRIDOR 2  id: ________   starts at corridor ______ at ______ m
   total length: ______ paces  = ______ m
   (repeat the table)
```

## What counts as "WHAT"

- **Room** → write the number/name exactly as on the door sign: `SJT 101`, `SJT 213A`
- **Stairs** → give it a name and **reuse that same name on every floor**: `st_north`, `st_main`
- **Lift** → same: `lift_main`
- **Washroom**, water cooler, printer, ATM, food
- **Entrance/exit** to outside

## The three things people forget

1. **Which floors each staircase actually reaches.** Write it down at the stairwell: `st_north → G,1,2,3 only`. This matters more than room accuracy — get it wrong and whole floors become unreachable.
2. **Whether the lift is genuinely usable** — staff-only? permanently broken? card-access? This is what step-free routing depends on for real wheelchair users.
3. **Where a corridor turns.** Note the distance at the corner and start a new corridor there.

## Photo shortcuts

Photograph: every stairwell sign listing floors, any wing/floor directory board, and door plates you can't transcribe fast enough. Faster than writing, and you can zoom in later.

---

## Transcribing (after you're back)

Copy `app/surveys/SJT.survey` and fill it in. Your table converts almost line for line:

```
building SJT "Silver Jubilee Tower" alias=SJT,Tower

floor f0 level=0 "Ground Floor"
corridor c_main length=60 heading=E          # just the length you paced

entrance 0 L e_main
room 8 L SJT101 "SJT 101" classroom alias=101
room 8 R SJT102 "SJT 102" classroom alias=102
poi 15 R washroom
stair 30 R st_main
lift 34 R lift_main
room 45 L SJT103 "SJT 103" lab alias=103 tag:dept=Physics
```

If a floor has a second corridor branching off:

```
corridor c_wing length=40 heading=S start=60,20
room 12 L SJT120 "SJT 120" classroom
link c_main 60 c_wing 0
```

Then:

```bash
cd app
dart run tool/survey/survey_to_bundle.dart surveys/SJT.survey
flutter run
```

The generator refuses to write a broken map and names the problem — unreachable rooms, a stair recorded on only one floor, a distance longer than its corridor. Fix and re-run.

---

**If transcribing is a pain, don't fight it** — send me your raw notes (typed or photographed) exactly as written and I'll produce the `.survey` file for you. Getting the data out of the building is the part only you can do; formatting it is the part I can do.
