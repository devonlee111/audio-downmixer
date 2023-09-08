#! /bin/bash

# don't exit on error
set +e

INPUT_FILE=""
CHANNEL_5_1="5.1(side)"
CHANNEL_STEREO="stereo"

# List of popular containers
# Taken from answer on this superuser question
# https://superuser.com/questions/300897/what-is-a-codec-e-g-divx-and-how-does-it-differ-from-a-file-format-e-g-mp
MEDIA_CONTAINERS=(".avi" ".mp4" ".mkv" ".webm")

# List of common lossless and lossy audio formats supported by container list
# List of supported codecs curated to include most likely/widely used codecs
# Taken from wikipedia
# https://en.wikipedia.org/wiki/Comparison_of_video_container_formats
# Listed names are short names derived from ffmpeg source code
LOSSLESS_AUDIO_CODECS=("alac" "mp4als" "dtshd" "flac" "mlp" "truehd")
LOSSY_AUDIO_CODECS=("aac" "ac3" "atrac3" "dts" "eac3" "mp1" "mp2" "mp3" "opus" "vorbis")

# Downmix Functions
# Taken from answers on this superuser question
# https://superuser.com/questions/852400/properly-downmix-5-1-to-stereo-using-ffmpeg
DOWNMIX_DAVE_750="pan=stereo|c0=0.5*c2+0.707*c0+0.707*c4+0.5*c3|c1=0.5*c2+0.707*c1+0.707*c5+0.5*c3"
DOWNMIX_ROBERT_COLLIER="pan=stereo|c0=c2+0.30*c0+0.30*c4|c1=c2+0.30*c1+0.30*c5"

containsElement () {
	local e match="$1"
	shift
	for e; do [[ "$e" == "$match" ]] && return 0; done
	return 1
}

STREAMS="$(ffprobe -show_entries stream=index,codec_type,codec_name,sample_rate,channel_type,channel_layout:stream_tags=language -of compact "$INPUT_FILE" -v 0 | grep audio)"

if [[ "$STREAMS" == *"$CHANNEL_STEREO"* ]]; then
	echo "has stereo audio"
	echo "nothing to do"
	exit
fi

echo "no stereo audio detected"
echo "attempting to downmix from 5.1 audio"

# TODO detect other 5.1 formats
if [[ "$STREAMS" == *"$CHANNEL_5_1"* ]]; then
	echo "has 5.1 audio"
	echo "need to downmix"

	declare -A STREAM_INFO

	INDEX_PREFIX="index="
	CODEC_PREFIX="codec_name="
	SAMPLE_RATE_PREFIX="sample_rate="
	LANGUAGE_PREFIX="tag:language="

	while IFS= read -r line; do
		echo "... $line ..."

		INDEX=$(echo "$line" | awk -f '|' '{print $2}')
		INDEX="${INDEX:$INDEX_PREFIX}}"
		CODEC=$(echo "$line" | awk -f '|' '{print $2}')
		CODEC="${CODEC:$CODEC_PREFIX}}"
		SAMPLE_RATE=$(echo "$line" | awk -f '|' '{print $2}')
		SAMPLE_RATE="${SAMPLE_RATE:$SAMPLE_RATE_PREFIX}}"
		LANGUAGE=$(echo "$line" | awk -f '|' '{print $2}')
		LANGUAGE="${LANGUAGE:$LANGUAGE_PREFIX}}"

		LOSSLESSNESS=""
		if containsElement "$CODEC" "${LOSSLESS_AUDIO_CODECS[@]}"; then
			echo "lossless codec"
			LOSSLESSNESS="lossless"
		elif containsElement "$CODEC" "${LOSSY_AUDIO_CODECS[@]}"; then
			echo "lossy codec"
			LOSSLESSNESS="lossy"
		else
			echo "unsupported codec"
			exit
		fi

		SHORTENED_INFO="$INDEX|$LOSSLESSNESS|$SAMPLE_RATE"

		if [[ -z "${STREAM_INFO[$LANGUAGE]}" ]]; then
			echo "new language detected: $LANGUAGE"
			STREAM_INFO["LANGUAGE"]="$SHORTENED_INFO"
		else
			echo "language already exists"
			EXISTING_INFO=${STREAM_INFO["$LANGUAGE"]}
			EXISTING_LOSSLESSNESS=$(echo "$EXISTING_INFO" | awk -F '|' '{print $2}')
			EXISTING_SAMPLE_RATE=$(echo "$EXISTING_INFO" | awk -F '|' '{print $2}')

			if [[ "$EXISTING_LOSSLESSNESS" == "$LOSSLESSNESS" ]]; then
				echo "both same losslessness"
				echo "$SAMPLE_RATE"
				echo "$EXISTING_SAMPLE_RATE"
				if [[ "SAMPLE_RATE" -le "$EXISTING_SAMPLE_RATE" ]]; then
					echo "sample rate lower or same... nothing to do"
				else
					echo "replacing with higher sample rate"
					STREAM_INFO["$LANGUAGE"]="$SHORTENED_INFO"
				fi
			elif [ "$LOSSLESSNESS" == "lossless" ] && [ "$EXISTING_LOSSLESSNESS" == "lossy" ]; then
				echo "replacing with lossless version"
				STREAM_INFO["$LANGUAGE"]="$SHORTENED_INFO"
			else
				echo "already has higher lossless codec"
			fi
		fi
	done <<< "$STREAMS"

	echo "${!STREAM_INFO[@]}"
	echo "${STREAM_INFO[@]}"
	exit
else
	echo "no valid audio tracks found"
fi