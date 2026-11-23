# Level design

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
SAM WAITIN - AFTERMATH   40.4s   140 BPM   93 beats   (first 40s of 182s)
level     498 m    start +30  to  finish -468
wall      12.32 m/s   =  88% of top speed
sprint    35.6s flat out    slack +4.8s
verdict   tough but fair
```

**`level_seconds`** on the level root is how much of the track the level uses.
0 means all of it. Shortening a level is that one number plus moving the
finish — never a re-chart.

Set it to a **break in the music**, not a round number. Aftermath drops out at
40.41s (beat 93.5) and stays quiet for two and a half seconds, so that is where
its level ends. Crossing the line does not cut the track: it plays on to that
point and washes out through a reverb there, so the tally assembles over the
last of the music and then the break. A good run finishes several seconds early
— that early arrival is what the slack is for — and still gets the same outro.

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
