# Storm Stitch

Outrun the storm. Stitch the world back together.

A 2-minute roguelite runner for iPhone and iPhone Duo. This repo holds the gray-box prototype (build step 1): the run itself, in plain shapes, so we can tune how it feels before any art goes in.

## Run it on your iPhone

1. Install XcodeGen once: `brew install xcodegen`
2. In this folder, run `xcodegen` to create `StormStitch.xcodeproj`.
3. Open `StormStitch.xcodeproj`, select the StormStitch target, and set your Team under Signing & Capabilities.
4. Pick your iPhone 17 Pro Max or iPhone Duo and press Run.

Change the bundle ID in `project.yml` if `com.adambellow.stormstitch` doesn't match your App Store Connect record, then run `xcodegen` again.

## Controls

- Swipe left or right: change lane (you can chain swipes without lifting your finger)
- Tap: jump (an early tap just before landing still counts)
- Swipe down: slide under bars
- Swipe down in the air: slam to the ground

## What's in the prototype

- Three lanes with a camera behind the runner, matching the hero style frame
- Three hazards: low blocks (jump), overhead bars (slide), crates (change lane)
- Spool lines in the open lane, and spool arcs over low blocks that reward a jump
- 3 hearts, and a storm wall that closes in with each hit and drops back over time
- Speed and hazard density ramp up across a 2-minute run
- Haptics on lane changes, jumps, landings, pickups and hits
- A live tuning panel (slider button, top left) for every feel number

## Feel checklist

Play 5 runs, then note answers to these:

1. Do lane changes feel instant? If not, lower Lane switch time or Swipe threshold.
2. Does tap-to-jump ever fire when you meant to swipe? If so, raise Swipe threshold.
3. Do jumps feel snappy or floaty? Adjust Gravity and Fall multiplier.
4. Is the first 20 seconds too easy or too hard? Adjust Start speed and Rows apart at start.
5. Does the storm feel scary but fair? Adjust Storm gain per hit and Storm fall-back rate.
6. Do you want one more run? That's the real test.

Send the numbers that feel best and they become the new defaults in `Tuning.swift`.

## Next steps

- Step 2: pick-3 power gates at 0:25, 0:50 and 1:15, and the first boss chase
- Step 3: the 8 monsters
- Art direction lives on the Storm Stitch Art Direction canvas
