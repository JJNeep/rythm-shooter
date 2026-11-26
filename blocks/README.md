# Level design

## The tutorial

`levels/tutorial.tscn`, refereed by `tutorial.gd`. Press **T** from a run, or
ENTER from the tutorial to leave for one.

It teaches by getting in the way. Each station is an obstacle that exactly one
mechanic clears, and the prompt only ever says which button and how its timing
works — never what you need, because the obstacle has already said that:

| Station | What blocks you | What it teaches |
|---|---|---|
| 1 Move | nothing | WASD, and that lane strips are one beat apart |
| 2 Shoot | a gate that opens after 4 clean hits | the gun fires only on the beat |
| 3 Jump | a 1.6 m step, then a 7 m hole | SPACE, and the energy bar |
| 4 Dash | a **21 m** hole — a jump reaches 17.7 m | SHIFT, and that dashing on the beat doubles its reach |
| 5 Rocket | a platform **8 m** up — a jump clears 1.96 m | fire at your own feet to launch |
| 6 Gunners | two gunners firing on alternate beats | the two-beat telegraph |
| 7 Wall | the wall, chasing at 9.6 m/s | the wall is the song's playhead |

Every distance there is checked against the reach table below, so no station
can dead-end. Nothing in it can fail either: energy never ends the run, falling
puts you back at the top of the station you are on, being caught by the wall
says so and resets the sprint, and ENTER leaves at any point.

If a player whiffs six shots at station 2, the goal line offers **F** — late
audio reads exactly like no rhythm, and they will believe the second
explanation unless you offer the first.

Open `levels/aftermath.tscn`. Drag any scene from this folder into the 3D
viewport. Save, press **F5**.

Nothing in a level is built in code. Every platform, wall, lane strip, light,
gunner and target is an ordinary node saved in the scene file — click it, move
it, delete it, change its material. If every script in the project vanished,
the level would still be there in full.

## The palette

| Drag in | What it is |
|---|---|
| `Floor` | ground you run along, 16 wide |
| `Wall` | side wall or backstop |
| `Platform` | a ledge or island |
| `Ledge` | thin balcony, for gunners |
| `Pillar` | cover you weave around |
| `Bridge` | narrow span over the void |
| `Ramp` | tilted 30°, run up it without spending a rocket |
| `Glass` | see-through floor, good for catch ledges |
| `Pad` | glowing green, for the finish |
| `Start` | the spawn. One per level |
| `Finish` | the end. One per level |

Enemies are their own scenes from the project root, not markers:

| Drag in | What it is |
|---|---|
| `ranged_enemy.tscn` | a gunner. Set `period` and `offset` on the node |
| `target.tscn` | static, shoot it for energy and combo |

A gunner fires on beat `offset` of every `period` beats, so neighbours with
different offsets alternate instead of firing as one wall of noise.

Blocks are grouped under one node per space (`S07_Bridge` and so on). Select
the group to move a whole space at once.

### Resizing a block

A block is a `StaticBody3D` holding `Mesh`, `Collision` and `Strips`. Its shape
lives in two places that have to agree: the **BoxMesh** under `Mesh` and the
**BoxShape3D** under `Collision`.

Blocks of the same size **share** those two resources, on purpose — it keeps
the file small and lets you restyle a whole level at once. The flip side is
that editing one 16×1×24 floor edits every 16×1×24 floor. To change just one,
right-click the resource in the inspector and pick **Make Unique** first.

Materials are shared too, as files in `blocks/materials/`. Recolouring every
floor in the game is one file.

## The pacing contract

The wall leaves `wall_back` metres behind **Start** and arrives at **Finish**
exactly as the level's slice of the song runs out. So its *speed is derived*,
never set: move the finish further away and the wall speeds up to keep its
appointment.

Which means the song always ends when the wall reaches the end, for any level
you build. The only number that can go wrong is how fast that forces the wall
to go. Select the level root and read `report`, or look at the readout floating
over the start line:

```
SAM WAITIN - AFTERMATH   84.3s   140 BPM   196 beats   (first 84s of 182s)
level     1050 m    start +30  to  finish -1020
wall      12.45 m/s   =  89% of top speed
sprint    75.0s flat out    slack +9.3s
verdict   tough but fair
```

**`level_seconds`** on the level root is how much of the track the level uses.
0 means all of it. Shortening a level is that one number plus moving the
finish — never a re-chart.

Set it to an **edge in the music**, not a round number. Aftermath breaks down
from 69.5s, thinning to near silence, and the drop lands on beat 197. The level
ends on **bar 50 (beat 196, 84.34s)**, the last edge in that silence — so the
contract lands the finish line on bar 50 too, exactly, and the level is 49 bars
long. The other candidate is the shorter break at 40.41s (beat 93.5).

Crossing the line does not cut the track: it plays on to `level_seconds` and
stops there. Because Aftermath's end point is the bottom of a fifteen-second
decay the artist already wrote, what you hear is the song running itself out
while the tally goes up. There is nothing left for the game to add, so it adds
nothing — 0.12s of fade, just enough not to click.

A good run crosses the line several seconds early; that early arrival is what
the slack is, and it gets the same ending. Dying instead switches the music off
over 0.7s, a filter closing rather than a fade.

Two things were tried here and were worse, so don't reach for them again. A
reverb tail had nothing to ring at a break in the music, and smeared whatever
followed the break into a wash. Seeking to the track's own last bars jumped
**+36 dB** out of that silence, because this track does not wind down at the
end — it plays flat out and stops at 181.6s. The lesson generalises: pick an
end point where the music has already resolved, then leave it alone.

The run also ends the player: no movement, no camera, and the mouse comes back
so the tally can be read.

**Slack** is the whole budget for climbs, fights and mistakes. Below about 55%
the wall cannot catch anyone; above about 95% one slip ends the run.

## Placing things on a beat

Tick **`show_beat_ruler`** on the level root. Numbered posts appear down the
lane showing where each beat lands in space, so a gunner you want firing as
the player arrives goes next to the post with that beat on it.

The ruler and the floating report are the only things any script adds, they
exist in the editor only, and neither is ever saved into the level.

## What the player can actually reach

Forward is **-Z**. A floor's walkable surface is its top face.

| Move | Reach |
|---|---|
| running jump, level ground | **17.7 m** |
| jump + sloppy dash | 18.6 m |
| jump + dash dead on the beat | **34.4 m** |
| highest step a jump clears | **1.96 m** |
| rocket straight down at your feet | **37.2 m** of lift |

So a gap decides its own answer. Under 17 m is free. 20 m needs any dash.
27 m needs a dash timed to about 66%. Anything rising more than 2 m needs a
rocket, and the launcher holds two charges that take four beats each to come
back — two climbs in a row spends the clip, three does not work.

Lane strips sit every 6 m, which is one beat of travel at full sprint. They
are a ruler you can see while playing.
