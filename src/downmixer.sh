#! /bin/bash

INPUT_FILE=""
CHANNEL_5_1="5.1(side)"
CHANNEL_STEREO="stereo"

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
