# World soundtracks

Each world plays its own song once `StormStitch/Sounds/music-<world>-base.caf` and
`music-<world>-drive.caf` exist (world ids: `canyon`, `lagoon`, `peaks`). Until then the game's
built-in synth plays that world in its own colors: a twangy pluck in E minor for Cardboard Canyon,
a bubbly marimba in A minor for Ink Lagoon, a koto pluck over taiko for Origami Peaks. Like the
existing songs, every world song has two layers of the same 16-bar loop: a calm **base** that
always plays, and a full **drive** layer the game fades in as the storm closes in.

## Cues

| Cue | When it plays | Files | Until the files exist |
| --- | --- | --- | --- |
| World song | Every stage in that world | `music-<world>-base.caf`, `music-<world>-drive.caf` | The synth in the world's colors (Notebook Meadow has its song already) |
| Shredder chase | The whole of every world's stage 10, the Shredder chase finale. The drive layer plays at full strength the whole way | `music-chase-base.caf`, `music-chase-drive.caf` | The synth's chase mode: 138 BPM, D minor with a sinister Eb, a pounding low pulse and a creeping chromatic lead |
| Victory sting | Reaching the seam gate and winning (3 to 6 s). The music ducks under it | `sting-victory.caf` | A synthesized fanfare: a rising stitch-zip run, ta-ta-taaa brass, a ringing D major chord |
| Fail sting | After the Shredder's laugh when a run is lost, and when a holiday rival beats you to the gate (2 to 4 s). The music ducks under it | `sting-fail.caf` | A synthesized sad-trombone "wah, wah, wah, waaah" with a thread-snap plink |

A lost chase finale plays the Shredder's own defeat sting (`storm-defeat.caf`) instead of the fail
sting, so only one sting ever plays at the end of a run.

## 1. Set up ACE-Step on your Mac (once)

```
cd ~/Documents
git clone https://github.com/ace-step/ACE-Step-1.5
cd ACE-Step-1.5
./install_uv.sh
./quick_test.sh
```

Then start the server (see the repo's README for the current command) and check it:

```
cd .claude/skills/acestep && ./scripts/acestep.sh health
```

Check the license of the model weights you download before shipping music made with them.

## 2. Make each song

Run every command from `ACE-Step-1.5/.claude/skills/acestep/`. Make the **drive** take first,
listen, and keep the one you like (each run gives 2 takes). Then make the **base** from it with
`cover`, which keeps the melody and timing but strips it back. Files land in `acestep_output/`.

All three share the game's sound: fun-spooky, 118 BPM, about 33 seconds (16 bars), instrumental.

### Cardboard Canyon

```
./scripts/acestep.sh generate -c "playful spooky western, twangy surf guitar, stomping cardboard-box percussion, plucky banjo, whistled hook, bouncy upright bass, mischievous and bright, polished game soundtrack, instrumental" -l "[Intro] [Instrumental] [Chorus - catchy whistled hook] [Instrumental] [Outro]" --duration 34 --bpm 118 --key-scale "E minor" --batch 2
```

### Ink Lagoon

```
./scripts/acestep.sh generate -c "playful spooky surf rock, tremolo guitar, upright bass, brushed snare, bubbling marimba, splashy toy percussion, mischievous and bright, polished game soundtrack, instrumental" -l "[Intro] [Instrumental] [Chorus - catchy marimba hook] [Instrumental] [Outro]" --duration 34 --bpm 118 --key-scale "A minor" --batch 2
```

### Origami Peaks

```
./scripts/acestep.sh generate -c "epic playful spooky adventure, plucked koto, taiko and toy drums, soaring flute hook, paper-crinkle percussion, driving strings, heroic and mischievous, polished game soundtrack, instrumental" -l "[Intro] [Build] [Chorus - heroic flute hook] [Instrumental] [Outro]" --duration 34 --bpm 118 --key-scale "D minor" --batch 2
```

### The Shredder chase

Same tempo and key family as the rest (118 BPM, D minor, like Origami Peaks and the synth), so it
sits right next to every world. Keep it tense but still fun: a cartoon villain, not a horror film.

```
./scripts/acestep.sh generate -c "tense playful spooky chase, pounding low toms and driving double-time drums, menacing low brass ostinato, staccato strings, sinister theremin lead, ticking clock, snipping scissors percussion, urgent and mischievous cartoon villain, polished game boss soundtrack, instrumental" -l "[Intro] [Build] [Chorus - menacing brass and theremin hook] [Instrumental] [Outro]" --duration 34 --bpm 118 --key-scale "D minor" --batch 2
```

For its base layer use the cover command below with this caption instead, so the chase stays
tense even before the drive layer comes in (it's at full strength for most of a chase anyway):

```
./scripts/acestep.sh cover acestep_output/<your-chase-drive-take>.mp3 -c "the same chase stripped back: no drums, a pulsing low string ostinato, ticking clock and soft timpani only, tense and creeping, instrumental" -l "[Intro] [Instrumental] [Chorus] [Instrumental] [Outro]" --duration 34 --bpm 118 --cover-strength 0.85
```

### The stings

ACE-Step makes whole clips, so ask for about 10 seconds and cut the best few seconds out with
`make_sting.sh` (step 3). Listen for where the sting starts and ends cleanly.

Victory (keep 3 to 6 s):

```
./scripts/acestep.sh generate -c "short bright triumphant fanfare jingle, quick rising pizzicato run into bold brass, glockenspiel sparkle, sewing-machine stitch percussion, cheerful toy orchestra, ends on one big ringing major chord, game level-complete sting, instrumental" -l "[Instrumental]" --duration 10 --bpm 118 --key-scale "D major" --batch 2
```

Fail (keep 2 to 4 s):

```
./scripts/acestep.sh generate -c "short playful sad cartoon fail jingle, descending sad trombone wah wah wah waaah, muted trumpet, plucked bass bonks, gentle wobble on the last note, comedic not gloomy, game over sting, instrumental" -l "[Instrumental]" --duration 10 --bpm 118 --key-scale "D minor" --batch 2
```

### The base layer, for each song

```
./scripts/acestep.sh cover acestep_output/<your-drive-take>.mp3 -c "the same song stripped back: no drums, soft plucked melody, light pads and bass only, calm and curious, instrumental" -l "[Intro] [Instrumental] [Chorus] [Instrumental] [Outro]" --duration 34 --bpm 118 --cover-strength 0.85
```

## 3. Put it in the game

```
cd ~/Documents/storm-stitch/tools/music
./make_song.sh canyon ~/Documents/ACE-Step-1.5/acestep_output/<base>.mp3 ~/Documents/ACE-Step-1.5/acestep_output/<drive>.mp3
```

The first argument is only the name in the file names, so the chase works the same way:

```
./make_song.sh chase ~/Documents/ACE-Step-1.5/acestep_output/<chase-base>.mp3 ~/Documents/ACE-Step-1.5/acestep_output/<chase-drive>.mp3
```

That writes `music-chase-base.caf` and `music-chase-drive.caf`; every stage 10 picks them up.

For the stings, give the length to keep and, if the good part doesn't start at the top, where it
starts (both in seconds):

```
./make_sting.sh victory ~/Documents/ACE-Step-1.5/acestep_output/<victory-take>.mp3 4.5 0.2
./make_sting.sh fail ~/Documents/ACE-Step-1.5/acestep_output/<fail-take>.mp3 3
```

It matches the songs' loudness, adds a 5 ms fade in and a 0.25 s fade out, and writes a mono
44.1 kHz ALAC `sting-victory.caf` or `sting-fail.caf` into `StormStitch/Sounds`.

Then `xcodegen` and build. Play a Cardboard Canyon stage and listen for the loop point (it should
never click or skip) and for the drive layer swelling in as the storm closes. Play any stage 10
for the chase, then win one stage and lose one for the stings.

Claude can't hear audio: you pick the takes by ear. If a take is close, send Claude what's off
("too slow", "the hook is muddy") and it will rewrite the caption.
