# Storm Stitch

Outrun the storm. Stitch the world back together.

A 2-minute roguelite runner for iPhone and iPhone Duo. This repo holds the vertical slice: Notebook Meadow with Bramble, polished to the bar the full game needs to hit.

## Run it on your iPhone

1. Install XcodeGen once: `brew install xcodegen`
2. In this folder, run `xcodegen` to create `StormStitch.xcodeproj`.
3. Open `StormStitch.xcodeproj`, select the StormStitch target, and set your Team under Signing & Capabilities.
4. Pick your iPhone 17 Pro Max or iPhone Duo and press Run.

Sound follows the silent switch, like most games. Flip it off to hear the music.

Change the bundle ID in `project.yml` if `com.adambellow.stormstitch` doesn't match your App Store Connect record, then run `xcodegen` again.

## Controls

- Swipe left or right: change lane
- Tap: jump (an early tap just before landing still counts)
- Swipe down: slide under rulers
- Swipe down in the air: slam to the ground

## What's in the slice

- **The color flood.** Notebook Meadow starts gray and torn. Every spool zips a gold-stitched patch of color into the ground around you, and trees and flowers pop into color. Fill the Stitch meter and the whole world floods with color: "WORLD STITCHED!"
- **Pop-up hazards.** Erasers (jump), rulers on pencils (slide) and cardboard boxes (change lanes) fold up out of the page as they approach, and burst into paper scraps when you hit them.
- **Bramble.** A layered paper rig with a run cycle, swinging arms, squash and stretch, blinking, and leaning into lane changes.
- **The storm.** A churning wall with glowing eyes that rises behind you with every hit, throws paper scraps, rumbles with thunder, and flashes red when it's about to catch you.
- **Game feel.** Camera follow, lean and speed push, hit-stop, screen shake, slow-mo on close calls, rising chimes on spool streaks, dust puffs, sparkles and confetti.
- **Sound and music.** A catchy, fun-spooky groove that builds with the run, plus synthesized effects for every action.
- **Screens.** An animated title, a results card with 3 stars (Finish, No hits, Stitched), stats and your best score.
- **Close calls.** Dodge a hazard at the last moment for +3 spools.

All art and audio are generated in code as stand-ins (`PaperArt.swift`, `GameAudio.swift`), so final illustrated assets and a composed score can be swapped in by name later.

## Feel tuning

The slider button (top left) adjusts every feel number live, plus toggles for music, sound, haptics and an FPS counter. Send the values that feel best and they become the defaults in `Tuning.swift`.

## Next steps

- Step 2: pick-3 power gates at 0:25, 0:50 and 1:15, and the first boss chase
- Step 3: the 8 monsters
- Art direction lives on the Storm Stitch Art Direction canvas
