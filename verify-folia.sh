#!/usr/bin/env bash

# verify-folia.sh
# Verifies the Folia runtime contract with a native build and synthetic fixtures.

set -euo pipefail

FOLIA_FFMPEG=${1:?Usage: verify-folia.sh FOLIA_FFMPEG [REFERENCE_FFMPEG]}
REFERENCE_FFMPEG=${2:-}
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

require_component() {
    local listing=$1
    local component=$2
    # Some FFmpeg components expose comma-separated aliases, for example
    # "mov,mp4,m4a,3gp,3g2,mj2", so commas are valid name boundaries too.
    if ! grep -Eq "(^|[[:space:],])$component([[:space:],]|$)" <<<"$listing"
    then
        echo "Missing required FFmpeg component: $component" >&2
        exit 1
    fi
}

decoders=$("$FOLIA_FFMPEG" -hide_banner -decoders)
demuxers=$("$FOLIA_FFMPEG" -hide_banner -demuxers)
encoders=$("$FOLIA_FFMPEG" -hide_banner -encoders)
muxers=$("$FOLIA_FFMPEG" -hide_banner -muxers)
filters=$("$FOLIA_FFMPEG" -hide_banner -filters)
protocols=$("$FOLIA_FFMPEG" -hide_banner -protocols)

for component in eac3 alac ape flac tta wavpack wmalossless wmapro wmav1 wmav2
do
    require_component "$decoders" "$component"
done
for component in mov caf aiff ape asf flac ogg tta wav wv
do
    require_component "$demuxers" "$component"
done
for component in flac pcm_s16le
do
    require_component "$encoders" "$component"
done
for component in flac wav null
do
    require_component "$muxers" "$component"
done
require_component "$filters" aresample
require_component "$protocols" file
require_component "$protocols" pipe

if grep -Eq '[[:space:]](http|https|tcp|udp|tls)([[:space:]]|$)' <<<"$protocols"
then
    echo "Network protocols must not be present in the Folia build" >&2
    exit 1
fi

python3 - "$WORK_DIR/input-96k.wav" <<'PY'
import math
import struct
import sys
import wave

sample_rate = 96000
with wave.open(sys.argv[1], 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(sample_rate)
    frames = bytearray()
    for index in range(sample_rate):
        sample = int(math.sin(2 * math.pi * 440 * index / sample_rate) * 8192)
        frames.extend(struct.pack('<h', sample))
    output.writeframes(frames)
PY

"$FOLIA_FFMPEG" -hide_banner -nostdin -v error -xerror -y \
    -i "$WORK_DIR/input-96k.wav" -map 0:a:0 -vn -sn -dn -map_metadata -1 \
    -ac 2 -c:a flac -compression_level 5 -f flac "$WORK_DIR/output-96k.flac"

decode_log=$("$FOLIA_FFMPEG" -hide_banner -nostdin -i "$WORK_DIR/output-96k.flac" \
    -map 0:a:0 -f null - 2>&1)
grep -q '96000 Hz' <<<"$decode_log"

if [ -n "$REFERENCE_FFMPEG" ]
then
    "$REFERENCE_FFMPEG" -hide_banner -nostdin -v error -y \
        -f lavfi -i sine=frequency=440:sample_rate=48000:duration=1 \
        -c:a eac3 -b:a 192k -tag:a ec-3 -f mp4 "$WORK_DIR/eac3.m4a"
    "$FOLIA_FFMPEG" -hide_banner -nostdin -v error -xerror -y \
        -i "$WORK_DIR/eac3.m4a" -map 0:a:0 -vn -sn -dn -map_metadata -1 \
        -ac 2 -c:a flac -compression_level 5 -f flac "$WORK_DIR/eac3.flac"
    "$FOLIA_FFMPEG" -hide_banner -nostdin -v error -xerror \
        -i "$WORK_DIR/eac3.flac" -map 0:a:0 -f null -

    "$REFERENCE_FFMPEG" -hide_banner -nostdin -v error -y \
        -f lavfi -i sine=frequency=880:sample_rate=96000:duration=1 \
        -c:a pcm_s16le "$WORK_DIR/input.caf"
    "$FOLIA_FFMPEG" -hide_banner -nostdin -v error -xerror -y \
        -i "$WORK_DIR/input.caf" -map 0:a:0 -vn -sn -dn -map_metadata -1 \
        -ac 2 -c:a flac -compression_level 5 -f flac "$WORK_DIR/caf.flac"
fi

echo "Folia FFmpeg verification passed"
