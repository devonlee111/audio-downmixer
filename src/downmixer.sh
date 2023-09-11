#! /bin/bash

# don't exit on error
set +e

inputFile="$1"
outputFile="downmixed-$1"

# Sample FFMPEG command
# Input stream has 2 5.1 audio streams in different languages that both need to be downmixed
# Audio streams are stream 0:1 and 0:2

# ffmpeg -i input.mkv -strict -2 -map 0:v -c:v copy -map 0:s -c:s copy -map 0:t -c:t copy
# -map 0:1 -map 0:1
# -c:a:0 copy
# -filter:a:1 "pan=stereo|c0=0.5*c2+0.707*c0+0.707*c4+0.5*c3|c1=0.5*c2+0.707*c1+0.707*c5+0.5*c3"
# -map 0:2 -map 0:2
# -c:a:2 copy
# -filter:a:3 "pan=stereo|c0=0.5*c2+0.707*c0+0.707*c4+0.5*c3|c1=0.5*c2+0.707*c1+0.707*c5+0.5*c3"
# output.mkv

CHANNEL_5_1=("channel_layout=5.1" "channel_layout=5.1(side)")
CHANNEL_STEREO="channel_layout=stereo"

# List of popular containers
# Taken from answer on this superuser question
# https://superuser.com/questions/300897/what-is-a-codec-e-g-divx-and-how-does-it-differ-from-a-file-format-e-g-mp
MEDIA_CONTAINERS=(".avi" ".mp4" ".mkv" ".webm")

# List of common lossless and lossy audio formats supported by container list
# List of supported cod:qecs curated to include most likely/widely used codecs
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

DONT_DOWNMIX="N/A"

# Base ffmpeg args for copying all video, subtitle, and ttf streams
FFMPEG_BASE_ARGS="-i $inputFile -map 0:v -c:v copy -map 0:s -c:s copy -map 0:t -c:t copy"

# Prefixes for information gathered from ffprobe commands
STREAM_INDEX_PREFIX="index="
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

# Use ffprobe to get audio stream information from file
audioStreams="$(ffprobe -show_entries stream=index,codec_type,codec_name,sample_rate,channel_type,channel_layout:stream_tags=language -of compact "$inputFile" -v 0 | grep audio)"

# Add ffmpeg base args as initial args for ffmpeg command
ffmpegCommand="$FFMPEG_BASE_ARGS"

downmixFunction="$DOWNMIX_ROBERT_COLLIER"

# Downmix 5.1 audio audioStreams to stereo
# TODO detect other 5.1 formats
declare -A streamInfo

# Index for audio output stream
# Needs to be kept track of since each audio stream is tracked seperately
audioOutputIndex=0
typeset -i audioOutputIndex

# Parse each audio stream to find highest quality 5.1 to downmix for each language
while IFS= read -r line; do
	# Extract relevant information
	streamIndex=$(echo "$line" | awk -F '|' '{print $2}')
	streamIndex="${streamIndex:${#STREAM_INDEX_PREFIX}}"
	codec=$(echo "$line" | awk -F '|' '{print $3}')
	codec="${codec:${#CODEC_PREFIX}}"
	sampleRate=$(echo "$line" | awk -F '|' '{print $5}')
	sampleRate="${sampleRate:${#SAMPLE_RATE_PREFIX}}"
	channel_layout=$(echo "$line" | awk -F '|' '{print $6}')
	language=$(echo "$line" | awk -F '|' '{print $7}')
	language="${language}:${#LANGUAGE_PREFIX}}"

	# Add args for copying current audio stream as is to preserve original
	ffmpegCopyArgs=" -map 0:$streamIndex -c:a:$audioOutputIndex copy"
	ffmpegCommand+="$ffmpegCopyArgs"
	audioOutputIndex+=1

	if [[ "$channel_layout" == "$CHANNEL_STEREO" ]]; then
		echo "stream is stereo. should not downmix for this language"
		streamInfo["$language"]="$DONT_DOWNMIX"
		continue
	fi

	if ! containsElement "$channel_layout" "${CHANNEL_5_1[@]}"; then
		echo "not 5.1 audio stream. don't do anything"
		continue
	fi

	# Check if current audio stream has 5.1 channel layout
	echo "stream is 5.1 should try to downmix"
	if [[ ${streamInfo["$language"]} == "$DONT_DOWNMIX" ]]; then
		# Check if don't downmix has been set already. Means there is already stereo audio
		echo "has stereo audio for language and should not downmix"
		continue
	fi

	# Should downmix
	# Check if codec is lossless or lossy
	# We are assuming that the lossless codec audioStreams are higher quality and haven't been lossily converted in the past
	losslessness=""
	if containsElement "$codec" "${LOSSLESS_AUDIO_CODECS[@]}"; then
		# Is a lossless codec
		echo "lossless codec"
		losslessness="lossless"
	elif containsElement "$codec" "${LOSSY_AUDIO_CODECS[@]}"; then
		# Is a lossy codec
		echo "lossy codec"
		losslessness="lossy"
	else
		# Is an unsupported codec
		echo "unsupported codec for downmixing"
		continue
	fi

	# Shortened info used for comparisons to find highest quality stream
	shortenedInfo="$streamIndex|$losslessness|$sampleRate"

	# Check if we've seen this language before
	if [[ -z "${streamInfo[$LANGUAGE]}" ]]; then
		# Is a language we haven't seen before. Add it to the map
		echo "new language detected: $language"
		streamInfo["$language"]="$shortenedInfo"
		continue
	fi

	# Is a language we have seen before. Need to compare streams for better downmixing source
	echo "language already exists"
	existingInfo=${streamInfo["$language"]}
	existingLosslessness=$(echo "$existingInfo" | awk -F '|' '{print $2}')
	existingSampleRate=$(echo "$existingInfo" | awk -F '|' '{print $3}')

	# Compare quality (based on metadata) of audioStreams to see if new stream is better than existing stream
	if [ "$losslessness" == "lossy" ] && [ "$existingLosslessness" == "lossless" ]; then
		# Already lossless source and current stream is lossy, so do nothing
		echo "already has higher lossless codec"
		continue
	elif [ "$losslessness" == "lossless" ] && [ "$existingLosslessness" == "lossy" ]; then
		# Replace stream to downmix with lossless source stream
		echo "replacing with lossless version"
		streamInfo["$language"]="$shortenedInfo"
		continue
	fi

	# Both are same losslessness. Compare sample rate
	echo "both same losslessness"
	if [[ "sampleRate" -le "$existingSampleRate" ]]; then
		# Compare samplerate for higher sample rate
		echo "sample rate lower or same... nothing to do"
		continue
	fi

	# Replace stream to downmix with higher quality source stream
	echo "replacing with higher sample rate"
	streamInfo["$language"]="$shortenedInfo"

done <<< "$audioStreams"

echo "${!streamInfo[@]}"
echo "${streamInfo[@]}"

downmixStreamCount=0

for key in "${!streamInfo[@]}"; do
	# Attempt do downmix chosen streams for each unique language audio stream
	echo "${key}, ${streamInfo[${key}]}"

	info=${streamInfo["$key"]}
	if [[ "$info" == "$DONT_DOWNMIX" ]]; then
		# Don't do anything if language marked as don't downmix
		continue
	fi

	index=$(echo "$info" | awk -F '|' '{print $1}')

	ffmpegDownmixArgs=" -map 0:$index -filter:a:$audioOutputIndex $downmixFunction"
	ffmpegCommand+="$ffmpegDownmixArgs"
	audioOutputIndex+=1
	downmixStreamCount+=1
done

if [[ "$downmixStreamCount" == 0 ]]; then
	echo "no downmixing required"
	exit
fi

ffmpegCommand="ffmpeg $ffmpegCommand $outputFile"
echo "downmixing..."
eval "$($ffmpegCommand)"
