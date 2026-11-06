# Cutout rig tool

Builds a jointed character from separately painted parts and previews it before it goes in the game.

1. Put the cleaned part PNGs in `ArtSource/rig/<name>/`: body, sprout, arm-l, arm-r, foot-l, foot-r, and foot-kick (a bent leg with the sole facing the camera).
2. From `ArtSource/rig`, run `python3 ../../tools/rig/rig.py <name> <preview-folder>` to render a preview GIF and a key-pose sheet.
3. Adjust each part's scale, pivot and joint in `MANIFEST` at the top of `rig.py` until the preview looks right.
4. Export to the game: `python3 -c "import sys; sys.path.insert(0, '../../tools/rig'); import rig; rig.export('<name>', '../../StormStitch/Art')"`.

Seen from behind, arms must show the back of the hand and planted feet only the heel; only a kicked foot shows its sole.

That writes `<name>-rig.json` and `<name>-rig-<part>.png` into the Art folder. `CutoutRig(named:)` in `CutoutRig.swift` loads them.
