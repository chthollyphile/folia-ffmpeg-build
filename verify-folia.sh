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

for component in eac3 alac ape flac tta wavpack wmalossless wmapro wmav1 wmav2 \
    dsd_lsbf_planar dsd_msbf_planar dsd_msbf dst
do
    require_component "$decoders" "$component"
done
for component in mov caf aiff ape asf flac ogg tta wav wv dsf iff
do
    require_component "$demuxers" "$component"
done
for component in flac pcm_s16le pcm_s24le pcm_s32le
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

"${PYTHON:-python3}" - "$WORK_DIR/input-96k.wav" <<'PY'
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

# FFmpeg has no DSD encoder, so both DSD containers are written here: half a
# second of a 1 kHz tone at DSD64 from a first-order sigma-delta modulator, as
# DSF (LSB first, 4096-byte channel blocks) and DSDIFF (MSB first, bytes
# interleaved by channel).
"${PYTHON:-python3}" - "$WORK_DIR/input.dsf" "$WORK_DIR/input.dff" <<'PY'
import math
import struct
import sys

dsd_rate = 2822400
channels = 2
bit_count = dsd_rate // 2
bits = bytearray(bit_count)
integrator = 0.0
feedback = -1.0
step = 2 * math.pi * 1000 / dsd_rate
for index in range(bit_count):
    integrator += 0.5 * math.sin(step * index) - feedback
    feedback = 1.0 if integrator >= 0 else -1.0
    bits[index] = feedback > 0

def pack(msb_first):
    order = range(8) if msb_first else range(7, -1, -1)
    return bytes(
        sum(bits[offset + bit] << (7 - shift) for shift, bit in enumerate(order))
        for offset in range(0, bit_count, 8)
    )

lsb = pack(False)
blocks = b''.join(
    lsb[offset:offset + 4096].ljust(4096, b'\0') * channels
    for offset in range(0, len(lsb), 4096)
)
fmt = struct.pack('<IIIIIIQII', 1, 0, 2, channels, dsd_rate, 1, bit_count, 4096, 0)
with open(sys.argv[1], 'wb') as output:
    output.write(b'DSD ' + struct.pack('<QQQ', 28, 28 + 12 + len(fmt) + 12 + len(blocks), 0))
    output.write(b'fmt ' + struct.pack('<Q', 12 + len(fmt)) + fmt)
    output.write(b'data' + struct.pack('<Q', 12 + len(blocks)) + blocks)

def chunk(tag, body):
    return tag + struct.pack('>Q', len(body)) + body + b'\0' * (len(body) % 2)

prop = (b'SND ' + chunk(b'FS  ', struct.pack('>I', dsd_rate))
        + chunk(b'CHNL', struct.pack('>H', channels) + b'SLFTSRGT')
        + chunk(b'CMPR', b'DSD ' + bytes([14]) + b'not compressed'))
form = (b'DSD ' + chunk(b'FVER', struct.pack('>I', 0x01050000)) + chunk(b'PROP', prop)
        + chunk(b'DSD ', bytes(value for value in pack(True) for _ in range(channels))))
with open(sys.argv[2], 'wb') as output:
    output.write(b'FRM8' + struct.pack('>Q', len(form)) + form)
PY

# Folia brings every DSD input down to 88.2 kHz: FFmpeg decodes DSD64 at
# 352.8 kHz and DSD256 at 1411.2 kHz, which the FLAC encoder refuses.
for container in dsf dff
do
    "$FOLIA_FFMPEG" -hide_banner -nostdin -v error -xerror -y \
        -i "$WORK_DIR/input.$container" -map 0:a:0 -vn -sn -dn -map_metadata -1 \
        -ac 2 -ar 88200 -c:a flac -compression_level 5 -f flac "$WORK_DIR/$container.flac"
    decode_log=$("$FOLIA_FFMPEG" -hide_banner -nostdin -xerror -i "$WORK_DIR/$container.flac" \
        -map 0:a:0 -f null - 2>&1)
    grep -q '88200 Hz' <<<"$decode_log"
done

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
