# Cutout rig tool

Builds a jointed character from separately painted parts and previews it before it goes in the game.
The body, sprout and arms turn and bounce on joints; hands and feet swap between a few drawings as they move.

1. Paint the parts in ChatGPT (the prompts live in the cutout-rig skill): a body sheet, then a row of
   4 foot drawings (planted, push-off, kicked, passing) and a row of 4 arm drawings (hanging, forward,
   back, raised), all seen from the same side the camera sees. Only the left side; the right is mirrored.
2. Cut them: `cut.split(sheet)` returns clean parts left to right; `cut.leg_top_pivot` and
   `cut.shoulder_pivot` find the joints. Save mirrored `-r` copies and a `pivots.json` (see ArtSource/rig/bramble).
3. Any part that draws in front of the body (the kicked foot) needs a rounded top, not a flat cut.
4. Preview: `python3 tools/rig/rig.py ArtSource/rig/<name> <preview-folder>` and look at it.
   Tune scale, pivot and joint in `MANIFEST`, and the timing in `foot_pose` and `arm_pose`.
5. Export: `rig.export('StormStitch/Art')` (run with the parts folder as the first argument) writes
   `<name>-rig.json` and `<name>-rig-<drawing>.png`; `CutoutRig(named:)` loads them.
