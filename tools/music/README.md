# World soundtracks

Each world plays its own song once `StormStitch/Sounds/music-<world>-base.caf` and
`music-<world>-drive.caf` exist (world ids: `canyon`, `lagoon`, `peaks`). Until then it plays
Notebook Meadow's song. Like the existing songs, every world song has two layers of the same
16-bar loop: a calm **base** that always plays, and a full **drive** layer the game fades in as
the storm closes in.

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

### The base layer, for each song

```
./scripts/acestep.sh cover acestep_output/<your-drive-take>.mp3 -c "the same song stripped back: no drums, soft plucked melody, light pads and bass only, calm and curious, instrumental" -l "[Intro] [Instrumental] [Chorus] [Instrumental] [Outro]" --duration 34 --bpm 118 --cover-strength 0.85
```

## 3. Put it in the game

```
cd ~/Documents/storm-stitch/tools/music
./make_song.sh canyon ~/Documents/ACE-Step-1.5/acestep_output/<base>.mp3 ~/Documents/ACE-Step-1.5/acestep_output/<drive>.mp3
```

Then `xcodegen` and build. Play a Cardboard Canyon stage and listen for the loop point (it should
never click or skip) and for the drive layer swelling in as the storm closes.

Claude can't hear audio: you pick the takes by ear. If a take is close, send Claude what's off
("too slow", "the hook is muddy") and it will rewrite the caption.
