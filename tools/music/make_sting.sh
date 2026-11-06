#!/bin/bash
# Turns one ACE-Step take into a game sting: cut to length (from an optional start point), matched
# in loudness, with a short fade in and a gentle fade out so it never clicks, saved as a mono
# 44.1 kHz ALAC .caf in StormStitch/Sounds (the format the game's sound players load).
#
#   ./make_sting.sh victory take.mp3 [seconds] [start]    # 3 to 6 s, default 4.5
#   ./make_sting.sh fail take.mp3 [seconds] [start]       # 2 to 4 s, default 3
#
# Writes sting-victory.caf or sting-fail.caf. The game plays them in place of its synthesized stings.
# Needs ffmpeg (brew install ffmpeg) and afconvert (built into macOS).
set -euo pipefail
usage() { echo "usage: $0 victory|fail take.mp3 [seconds] [start]" >&2; exit 1; }
[ $# -ge 2 ] || usage
kind="$1"; src="$2"
case "$kind" in
  victory) default=4.5; min=3; max=6 ;;
  fail) default=3; min=2; max=4 ;;
  *) usage ;;
esac
seconds="${3:-$default}"; start="${4:-0}"
if ! python3 -c "import sys; sys.exit(0 if $min <= $seconds <= $max else 1)"; then
  echo "warning: a $kind sting should be $min to $max seconds; making it $seconds s anyway" >&2
fi
fade_out=0.25
fade_at=$(python3 -c "print(round($seconds - $fade_out, 4))")
out="$(cd "$(dirname "$0")/../../StormStitch/Sounds" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Loudness first (to the same target as the songs), then the fades, so the ends are sure to be silent.
ffmpeg -loglevel error -y -ss "$start" -i "$src" -t "$seconds" -ac 1 \
  -af "loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=in:d=0.005,afade=t=out:st=$fade_at:d=$fade_out" \
  -ar 44100 "$tmp/sting.wav"
afconvert -f caff -d alac -c 1 "$tmp/sting.wav" "$out/sting-$kind.caf"
echo "wrote $out/sting-$kind.caf"
echo "Run xcodegen, then build: the game now plays this $kind sting."
