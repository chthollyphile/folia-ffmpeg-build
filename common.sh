#!/usr/bin/env bash

FFMPEG_VERSION=8.1.2
FFMPEG_TARBALL=ffmpeg-$FFMPEG_VERSION.tar.gz
FFMPEG_TARBALL_URL=https://ffmpeg.org/releases/$FFMPEG_TARBALL
FFMPEG_TARBALL_SHA256=32faba5ef67340d54724941eae1425580791195312a4fd13bf6f820a2818bf22

# LAME is the MP3 encoder used by the encode variant. It is LGPL, which matches
# the license of these FFmpeg builds (configured without --enable-gpl), and is
# built statically from source for each target by build-lame.sh.
LAME_VERSION=3.100
LAME_TARBALL=lame-$LAME_VERSION.tar.gz
LAME_TARBALL_URL=https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/$LAME_TARBALL
LAME_TARBALL_SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1
    then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# Downloads a pinned source archive and rejects both transport and checksum failures.
download_verified() {
    local url=$1
    local destination=$2
    local expected_sha256=$3

    if [ ! -e "$destination" ]
    then
        curl --fail --location --retry 3 --output "$destination" "$url"
    fi

    local actual_sha256
    actual_sha256=$(sha256_file "$destination")
    if [ "$actual_sha256" != "$expected_sha256" ]
    then
        echo "Checksum mismatch for $destination" >&2
        echo "expected: $expected_sha256" >&2
        echo "actual:   $actual_sha256" >&2
        rm -f "$destination"
        return 1
    fi
}

# Adds the exact source/configuration record and licenses next to each binary.
install_distribution_metadata() {
    local output_dir=$1
    local metadata_dir=$output_dir/share/folia-ffmpeg

    mkdir -p "$metadata_dir"
    cp "$BASE_DIR/LICENSE" "$metadata_dir/build-scripts-MIT.txt"
    cp COPYING.LGPLv2.1 "$metadata_dir/FFmpeg-LGPL-2.1.txt"
    {
        echo "FFmpeg version: $FFMPEG_VERSION"
        echo "Source: $FFMPEG_TARBALL_URL"
        echo "Source SHA-256: $FFMPEG_TARBALL_SHA256"
        echo "Variant: $FFMPEG_VARIANT"
        printf 'Configure flags:'
        printf ' %q' "${FFMPEG_CONFIGURE_FLAGS[@]}"
        echo
    } > "$metadata_dir/BUILD-INFO.txt"
}

# Which build variant to produce:
#   decode - upstream audio decoder build used for Chromaprint/fpcalc
#   encode - decoders plus native audio encoders/muxers for transcoding,
#            including MP3 encoding via a statically linked libmp3lame
#   folia  - Folia playback fallback: audio decoders plus FLAC/PCM output,
#            complete-output validation and source sample-rate preservation
# No GPL-only or nonfree codecs are ever included, so the builds stay LGPL.
FFMPEG_VARIANT=${FFMPEG_VARIANT:-folia}

FFMPEG_CONFIGURE_FLAGS=(
    --disable-shared
    --enable-static
    --enable-pic

    --disable-doc
    --disable-debug
    --disable-avdevice
    --disable-swscale
    --disable-programs
    --enable-ffmpeg
    --enable-ffprobe
    --disable-network
    --disable-muxers
    --disable-demuxers
    --disable-zlib
    --disable-lzma
    --disable-bzlib
    --disable-iconv
    --disable-libxcb
    --disable-bsfs
    --disable-filters
    --disable-parsers
    --disable-indevs
    --disable-outdevs
    --disable-encoders
    --disable-decoders
    --disable-hwaccels
    --disable-nvenc
    --disable-videotoolbox
    --disable-audiotoolbox

    --disable-filters
    --enable-filter=aformat
    --enable-filter=anull
    --enable-filter=atrim
    --enable-filter=format
    --enable-filter=null
    --enable-filter=setpts
    --enable-filter=trim

    --disable-protocols
    --enable-protocol=file
    --enable-protocol=pipe

    --enable-demuxer=image2
    --enable-demuxer=aac
    --enable-demuxer=ac3
    --enable-demuxer=aiff
    --enable-demuxer=ape
    --enable-demuxer=asf
    --enable-demuxer=au
    --enable-demuxer=avi
    --enable-demuxer=flac
    --enable-demuxer=flv
    --enable-demuxer=matroska
    --enable-demuxer=mov
    --enable-demuxer=m4v
    --enable-demuxer=mp3
    --enable-demuxer=mpc
    --enable-demuxer=mpc8
    --enable-demuxer=ogg
    --enable-demuxer=pcm_alaw
    --enable-demuxer=pcm_mulaw
    --enable-demuxer=pcm_f64be
    --enable-demuxer=pcm_f64le
    --enable-demuxer=pcm_f32be
    --enable-demuxer=pcm_f32le
    --enable-demuxer=pcm_s32be
    --enable-demuxer=pcm_s32le
    --enable-demuxer=pcm_s24be
    --enable-demuxer=pcm_s24le
    --enable-demuxer=pcm_s16be
    --enable-demuxer=pcm_s16le
    --enable-demuxer=pcm_s8
    --enable-demuxer=pcm_u32be
    --enable-demuxer=pcm_u32le
    --enable-demuxer=pcm_u24be
    --enable-demuxer=pcm_u24le
    --enable-demuxer=pcm_u16be
    --enable-demuxer=pcm_u16le
    --enable-demuxer=pcm_u8
    --enable-demuxer=rm
    --enable-demuxer=shorten
    --enable-demuxer=tak
    --enable-demuxer=tta
    --enable-demuxer=wav
    --enable-demuxer=wv
    --enable-demuxer=xwma
    --enable-demuxer=dsf

    --enable-decoder=aac
    --enable-decoder=aac_latm
    --enable-decoder=ac3
    --enable-decoder=alac
    --enable-decoder=als
    --enable-decoder=ape
    --enable-decoder=atrac1
    --enable-decoder=atrac3
    --enable-decoder=eac3
    --enable-decoder=flac
    --enable-decoder=gsm
    --enable-decoder=gsm_ms
    --enable-decoder=mp1
    --enable-decoder=mp1float
    --enable-decoder=mp2
    --enable-decoder=mp2float
    --enable-decoder=mp3
    --enable-decoder=mp3adu
    --enable-decoder=mp3adufloat
    --enable-decoder=mp3float
    --enable-decoder=mp3on4
    --enable-decoder=mp3on4float
    --enable-decoder=mpc7
    --enable-decoder=mpc8
    --enable-decoder=opus
    --enable-decoder=ra_144
    --enable-decoder=ra_288
    --enable-decoder=ralf
    --enable-decoder=shorten
    --enable-decoder=tak
    --enable-decoder=tta
    --enable-decoder=vorbis
    --enable-decoder=wavpack
    --enable-decoder=wmalossless
    --enable-decoder=wmapro
    --enable-decoder=wmav1
    --enable-decoder=wmav2
    --enable-decoder=wmavoice

    --enable-decoder=pcm_alaw
    --enable-decoder=pcm_bluray
    --enable-decoder=pcm_dvd
    --enable-decoder=pcm_f32be
    --enable-decoder=pcm_f32le
    --enable-decoder=pcm_f64be
    --enable-decoder=pcm_f64le
    --enable-decoder=pcm_lxf
    --enable-decoder=pcm_mulaw
    --enable-decoder=pcm_s8
    --enable-decoder=pcm_s8_planar
    --enable-decoder=pcm_s16be
    --enable-decoder=pcm_s16be_planar
    --enable-decoder=pcm_s16le
    --enable-decoder=pcm_s16le_planar
    --enable-decoder=pcm_s24be
    --enable-decoder=pcm_s24daud
    --enable-decoder=pcm_s24le
    --enable-decoder=pcm_s24le_planar
    --enable-decoder=pcm_s32be
    --enable-decoder=pcm_s32le
    --enable-decoder=pcm_s32le_planar
    --enable-decoder=pcm_u8
    --enable-decoder=pcm_u16be
    --enable-decoder=pcm_u16le
    --enable-decoder=pcm_u24be
    --enable-decoder=pcm_u24le
    --enable-decoder=pcm_u32be
    --enable-decoder=pcm_u32le
    --enable-decoder=pcm_zork
    --enable-decoder=dsd_lsbf
    --enable-decoder=dsd_msbf
    --enable-decoder=dsd_lsbf_planar
    --enable-decoder=dsd_msbf_planar

    --enable-parser=aac
    --enable-parser=aac_latm
    --enable-parser=ac3
    --enable-parser=cook
    --enable-parser=dca
    --enable-parser=flac
    --enable-parser=gsm
    --enable-parser=mpegaudio
    --enable-parser=tak
    --enable-parser=vorbis
)

# Label used in the output directory / artifact name for each variant.
case $FFMPEG_VARIANT in
    decode)
        FFMPEG_VARIANT_LABEL=audio
        ;;
    encode)
        FFMPEG_VARIANT_LABEL=audio-encode
        # Audio encoders. MP3 has no native FFmpeg encoder, so it is provided by
        # libmp3lame, which the platform build scripts compile statically and
        # point at via --extra-cflags/--extra-ldflags.
        FFMPEG_CONFIGURE_FLAGS+=(
            --enable-libmp3lame
            --enable-encoder=libmp3lame
            --enable-muxer=mp3

            --enable-encoder=aac
            --enable-encoder=ac3
            --enable-encoder=eac3
            --enable-encoder=mp2
            --enable-encoder=flac
            --enable-encoder=alac
            --enable-encoder=wavpack
            --enable-encoder=tta
            --enable-encoder=opus
            --enable-encoder=vorbis
            --enable-encoder=wmav1
            --enable-encoder=wmav2
            --enable-encoder=pcm_s16le
            --enable-encoder=pcm_s16be
            --enable-encoder=pcm_s24le
            --enable-encoder=pcm_s32le
            --enable-encoder=pcm_f32le
            --enable-encoder=pcm_u8
            --enable-encoder=pcm_alaw
            --enable-encoder=pcm_mulaw

            --enable-muxer=wav
            --enable-muxer=w64
            --enable-muxer=aiff
            --enable-muxer=flac
            --enable-muxer=mp4
            --enable-muxer=ipod
            --enable-muxer=mov
            --enable-muxer=ogg
            --enable-muxer=oga
            --enable-muxer=opus
            --enable-muxer=wv
            --enable-muxer=ac3
            --enable-muxer=eac3
            --enable-muxer=asf
            --enable-muxer=mp2
            --enable-muxer=adts
            --enable-muxer=latm
            --enable-muxer=tta
            --enable-muxer=au
            --enable-muxer=caf
            --enable-muxer=matroska

            # Needed for sample-rate / sample-format conversion when transcoding.
            --enable-filter=aresample
        )
        ;;
    folia)
        FFMPEG_VARIANT_LABEL=folia
        FFMPEG_CONFIGURE_FLAGS+=(
            # Folia bundles only ffmpeg. ffprobe remains available in the
            # upstream variants but is not needed by the desktop runtime.
            --disable-ffprobe

            # CAF input is part of Folia's local-library extension contract.
            # E-AC-3 in .m4a uses the base mov demuxer + eac3 decoder.
            --enable-demuxer=caf

            --enable-encoder=flac
            --enable-encoder=pcm_s16le
            --enable-muxer=flac
            --enable-muxer=wav
            --enable-muxer=null

            # Lets FFmpeg convert channel/sample formats without forcing a
            # sample rate; 96 kHz inputs therefore remain 96 kHz.
            --enable-filter=aresample
        )
        ;;
    *)
        echo "Unknown variant: $FFMPEG_VARIANT" >&2
        exit 1
        ;;
esac
