#! /bin/bash

INPUT_FILE=""
CHANNEL_5_1="5.1(side)"
CHANNEL_STEREO="stereo"

# List of popular containers
# Taken from answer on this superuser question
# https://superuser.com/questions/300897/what-is-a-codec-e-g-divx-and-how-does-it-differ-from-a-file-format-e-g-mp
MEDIA_CONTAINERS="AVI,MP4,MKV,WebM,"

# List of lossless audio formats supported by container list
# Taken from wikipedia
# https://en.wikipedia.org/wiki/Comparison_of_video_container_formats
LOSSLESS_AUDIO_CODECS="ALAC,ALS,DTSHD,FLAC,MLP,SLS,TRUEHD,WMA"

# Downmix Functions
# Taken from answers on this superuser question
# https://superuser.com/questions/852400/properly-downmix-5-1-to-stereo-using-ffmpeg
DOWNMIX_DAVE_750="pan=stereo|c0=0.5*c2+0.707*c0+0.707*c4+0.5*c3|c1=0.5*c2+0.707*c1+0.707*c5+0.5*c3"
DOWNMIX_ROBERT_COLLIER="pan=stereo|c0=c2+0.30*c0+0.30*c4|c1=c2+0.30*c1+0.30*c5"

STREAMS="$(ffprobe -show_entries stream=index,codec_type,codec_name,channel_type,channel_layout:stream_tags=language -of compact "$INPUT_FILE" -v 0 | grep audio)"

if [[ "$STREAMS" == *"$CHANNEL_STEREO"* ]]; then
	echo "has stereo audio"
	echo "nothing to do"
fi

echo "no stereo audio detected"
echo "attempting to downmix from 5.1 audio"

if [[ "$STREAMS" == *"$CHANNEL_5_1"* ]]; then
	echo "has 5.1 audio"
	echo "need to downmix"
	exit
fi

echo "no valid audio tracks found"
