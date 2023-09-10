#! /bin/bash

# don't exit on error
set +e

# Sample FFMPEG command
# Input stream has 2 5.1 audio streams in different languages that both need to be downmixed

# ffmpeg -i input.mkv -strict -2 -map 0:v -c:v copy -map 0:s -c:s copy -map 0:t -c:t copy
# -map 0:1 -map 0:1
# -c:a:0 copy
# -filter:a:1 "pan=stereo|c0=0.5*c2+0.707*c0+0.707*c4+0.5*c3|c1=0.5*c2+0.707*c1+0.707*c5+0.5*c3"
# -map 0:2 -map 0:2
# -c:a:2 copy
# -filter:a:3 "pan=stereo|c0=0.5*c2+0.707*c0+0.707*c4+0.5*c3|c1=0.5*c2+0.707*c1+0.707*c5+0.5*c3"
# output.mkv

CHANNEL_5_1="5.1"
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

FFMPEG_BASE_ARGS="-i input.mkv -strict -2 -map 0:v -c:v copy -map 0:s -c:s copy -map 0:t -c:t copy"

# Prefixes for information gathered from ffprobe commands
INDEX_PREFIX="index="
CODEC_PREFIX="codec_name="
SAMPLE_RATE_PREFIX="sample_rate="
LANGUAGE_PREFIX="tag:language="

# Helper function to check if element exists in array
containsElement () {
	local e match="$1"
	shift
	for e; do [[ "$e" == "$match" ]] && return 0; done
	return 1
}

inputFile=$1

# Use ffprobe to get audio stream information from file
audioStreams="$(ffprobe -show_entries stream=index,codec_type,codec_name,sample_rate,channel_type,channel_layout:stream_tags=language -of compact "$inputFile" -v 0 | grep audio)"
ffmpegCommand="$FFMPEG_BASE_ARGS"

# Check if file already has stereo audio
# TODO check this for individual stream languages
if [[ "$audioStreams" == *"$CHANNEL_STEREO"* ]]; then
	echo "has stereo audio"
	echo "nothing to do"
	exit
fi

echo "no stereo audio detected"
echo "attempting to downmix from 5.1 audio"

# Downmix 5.1 audio audioStreams to stereo
# TODO detect other 5.1 formats
if [[ "$audioStreams" == *"$CHANNEL_5_1"* ]]; then
	echo "has 5.1 audio"
	echo "need to downmix"

	declare -A streamInfo

	audioOutputIndex=0
	typeset -i audioOutputIndex

	# Parse each audio stream to find highest quality 5.1 to downmix for each language
	while IFS= read -r line; do
		echo "... $line ..."

		# Extract relevant information
		streamIndex=$(echo "$line" | awk -F '|' '{print $2}')
		streamIndex="${streamIndex:${#STREAM_INDEX_PREFIX}}"
		codec=$(echo "$line" | awk -F '|' '{print $3}')
		codec="${codec:${#CODEC_PREFIX}}"
		sampleRate=$(echo "$line" | awk -F '|' '{print $5}')
		sampleRate="${sampleRate:${#SAMPLE_RATE_PREFIX}}"
		language=$(echo "$line" | awk -F '|' '{print $7}')
		language="${language}:${#LANGUAGE_PREFIX}}"

		ffmpegCopyArgs=" -map 0:$streamIndex -c:a:$audioOutputIndex copy"
		ffmpegCommand+="$ffmpegCopyArgs"
		audioOutputIndex+=1

		# Check if codec is lossless or lossy
		# We are assuming that the lossless codec audioStreams are higher quality and haven't been lossily converted in the past
		losslessness=""
		if containsElement "$codec" "${LOSSLESS_AUDIO_CODECS[@]}"; then
			echo "lossless codec"
			losslessness="lossless"
		elif containsElement "$codec" "${LOSSY_AUDIO_CODECS[@]}"; then
			echo "lossy codec"
			losslessness="lossy"
		else
			echo "unsupported codec"
			# TODO don't quit if any one codec is unsupported
			exit
		fi

		# Shortened info used for comparisons to find highest quality stream
		shortenedInfo="$streamIndex|$losslessness|$sampleRate"

		# Add new language audio track to list to be downmixed
		if [[ -z "${streamInfo[$LANGUAGE]}" ]]; then
			echo "new language detected: $language"
			streamInfo["$language"]="$shortenedInfo"
		else
			echo "language already exists"
			existingInfo=${streamInfo["$language"]}
			existingLosslessness=$(echo "$existingInfo" | awk -F '|' '{print $2}')
			existingSampleRate=$(echo "$existingInfo" | awk -F '|' '{print $3}')

			# Compare quality (based on metadata) of audioStreams to see if new stream is better than existing stream
			if [[ "$existingLosslessness" == "$losslessness" ]]; then
				echo "both same losslessness"
				if [[ "sampleRate" -le "$existingSampleRate" ]]; then
					echo "sample rate lower or same... nothing to do"
				else
					echo "replacing with higher sample rate"
					streamInfo["$language"]="$shortenedInfo"
				fi
			elif [ "$losslessness" == "lossless" ] && [ "$existingLosslessness" == "lossy" ]; then
				echo "replacing with lossless version"
				streamInfo["$language"]="$shortenedInfo"
			else
				echo "already has higher lossless codec"
			fi
		fi
	done <<< "$audioStreams"

	echo "${!streamInfo[@]}"
	echo "${streamInfo[@]}"

	for key in "${!streamInfo[@]}"; do
		echo "${key}, ${streamInfo[${key}]}"

		info=${streamInfo["$key"]}

		index=$(echo "$info" | awk -F '|' '{print $1}')

		FFMPEG_DOWNMIX_ARGS+=" -map 0:$index -filter:a:$audioOutputIndex \"$DOWNMIX_ROBERT_COLLIER\""
		ffmpegCommand+="$FFMPEG_ADDITIONAL_ARGS"
		audioOutputIndex+=1
	done

	echo "ffmpeg $ffmpegCommand output.mkv"
	exit
else
	echo "no valid audio tracks found"
fi
