# Finding a Combined CG — Notes to Self

*How we broke down the Mid Chute + Upper Chute combined centre of gravity problem, and the maths behind it.*

---

## The problem we were solving

Two separate parts — Mid Chute (14,950 kg) and Upper Chute (10,190 kg) — get bolted together into one stacked assembly. Each part has its own individual centre of gravity (CG), marked on its own engineering drawing. Once they're joined, the assembly has a **single combined CG** somewhere between the two — and that combined point is what actually matters for rigging, because that's the point the crane hook needs to sit above for a level lift.

The question: where exactly does that combined point land?

---

## Step 1 — Find each part's own CG

Each drawing had a small circle-and-crosshair mark showing that part's individual CG. To turn that mark into a real measurement, we scaled the drawing: using a dimension we already knew (like the 4415mm flange width, or the 2390mm overall height), we worked out how many real millimetres one pixel represented, then measured the CG mark's position using that scale.

Result:

| Part | CG horizontal (x) | CG height (z, above its own base) |
|---|---|---|
| Mid Chute | 2406mm | 1482mm |
| Upper Chute | 995mm | 1509mm |

## Step 2 — Put both parts on the same map

Once stacked, Upper Chute sits on top of Mid Chute's flange — 2390mm up. So Upper Chute's height figure needed the stack offset added to it, to express both CGs using one shared coordinate system (same zero point, same directions):

| Part | CG x (global) | CG z (global) |
|---|---|---|
| Mid Chute | 2406mm | 1482mm |
| Upper Chute | 995mm | 2390 + 1509 = **3899mm** |

Now both points can be compared and combined directly.

## Step 3 — The part that took the longest to click: it's *not* a simple midpoint

The instinct is to average the two positions 50/50. That would be correct **only if both parts weighed the same.** They don't — Mid Chute is noticeably heavier. So the combined CG has to sit closer to Mid Chute's own CG than to Upper Chute's, because the heavier part has more "pull."

The right tool for this is a **weighted average** — each part's position counted in proportion to its share of the total weight, not counted equally.

## Step 4 — The "vote share" way of thinking about it

This is the version that made it click:

```
Vote share of a part = that part's weight ÷ total weight of everything
```

```
Total weight = 14,950 + 10,190 = 25,140 kg

Mid Chute's vote share   = 14,950 ÷ 25,140 = 59.5%
Upper Chute's vote share = 10,190 ÷ 25,140 = 40.5%
```

The two shares always add up to 100% — between them, the two parts account for the entire weight being lifted.

**The rule that makes it usable:** whichever CG you start measuring from, the distance you travel toward the *other* one is set by the *other* part's vote share — not your own.

- Heavier part = bigger share = pulls the combined point toward itself, so *starting from it*, you only travel a short distance (using the *lighter* part's small share).
- Starting from the lighter part instead, you'd travel a longer distance (using the *heavier* part's bigger share) — but you're still travelling toward the same destination, just approached from the other end.

## Step 5 — Applying it along the direct line between the two CGs

Straight-line distance between the two individual CGs:

```
Distance = √[(2406−995)² + (1482−3899)²]
         = √[(1411)² + (−2417)²]
         = √7,832,810
         ≈ 2799mm
```

Then:

```
From Mid Chute's CG, using Upper's share:   2799mm × 0.405 = 1134mm
From Upper Chute's CG, using Mid's share:   2799mm × 0.595 = 1665mm

Check: 1134 + 1665 = 2799mm ✓ (the two partial trips add up to the full distance)
```

Either direction lands on the same combined point — landing closer to Mid Chute, exactly as the weight difference predicts.

## Step 6 — Full formula, stated plainly

```
Combined x = (m1·x1 + m2·x2) / (m1 + m2)
Combined z = (m1·z1 + m2·z2) / (m1 + m2)
```

Worked through:

```
Combined x = (14950×2406 + 10190×995) / 25140 = 1834mm
Combined z = (14950×1482 + 10190×3899) / 25140 = 2462mm
```

Same answer, three different ways of arriving at it (weighted average formula, vote-share percentage, direct-line travel distance) — a good sign the concept is solid, not just a lucky calculation.

## Step 7 — Checking it against reality

The whole exercise was built off scaled engineering drawings — approximate by nature. The real test came from the actual lift: leveling the stacked assembly with chain blocks produced a measured 1290mm difference between the two rigging legs. Reworking the same CG shift through the original engineered chain geometry (1939mm/19° and 4127mm/38°) predicted a **1321mm gap** — landing within **31mm** of the real-world result.

Two independent methods — drawing-based maths and physically hanging 25 tonnes on chain blocks — agreeing within 31mm is a solid confidence check that the underlying logic holds up outside the spreadsheet.

---

*Archive note: built from a working conversation, kept for personal reference — not tied to the Myslewer PWA codebase.*
