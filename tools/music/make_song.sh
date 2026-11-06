#!/bin/bash
# Turns two ACE-Step takes of one song (a calm "base" and a full "drive") into the game's looping
# layers: trimmed to exactly 16 bars so they stay locked together, matched in loudness, saved as
# ALAC .caf files in StormStitch/Sounds.
#
#   ./make_song.sh canyon base.mp3 drive.mp3 [bpm]
#
# Needs ffmpeg (brew install ffmpeg) and afconvert (built into macOS).
set -euo pipefail
world="$1"; base="$2"; drive="$3"; bpm="${4:-118}"
bars=16
seconds=$(python3 -c "print(round($bars * 4 * 60 / $bpm, 4))")
out="$(cd "$(dirname "$0")/../../StormStitch/Sounds" && pwd)"
tmp="$(mktemp -d)"
for layer in base drive; do
  src="$base"; [ "$layer" = drive ] && src="$drive"
  # Trim to the loop length with a 10 ms fade at each end so the loop point never clicks,
  # and bring both layers to the same loudness as the existing songs.
  ffmpeg -loglevel error -y -i "$src" -t "$seconds" -ar 44100 -ac 2 \
    -af "afade=t=in:d=0.01,afade=t=out:st=$(python3 -c "print($seconds - 0.01)"):d=0.01,loudnorm=I=-16:TP=-1.5:LRA=11" \
    "$tmp/$layer.wav"
  afconvert -f caff -d alac -c 2 "$tmp/$layer.wav" "$out/music-$world-$layer.caf"
  echo "wrote $out/music-$world-$layer.caf"
done
rm -rf "$tmp"
echo "Run xcodegen, then build: the $world stages now play this song."
