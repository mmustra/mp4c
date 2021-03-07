#!/usr/bin/env bash

################################################################################
#
#                                MP4 Converter
#
# The MIT License (MIT)
#
# Copyright (c) 2021 Marin Muštra (https://github.com/mmustra)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
################################################################################

################################################################################
#
# HOW TO USE
#
# > sh mp4c.sh [command] [extensions] [*ffmpegOptions] [path]
#
# [command] Required
#   scan - Find video files
#   convert - Convert video files to mp4 and create backups
#   convert-replace - Replace already converted files with new
#   revert - Revert original files (if backups exists)
#   clean - Clean and keep .mp4 files, remove backups
# [extensions] Required, one or more (separated with comma)
#   Ex. mts or MTS or .mts,.mov
# [*ffmpegOptions] Optional, used ONLY with convert and convert-replace command, defaults to copy
#   copy - Preserve video, audio AAC 256 kbps
#   1080p - Resize video to 1080p, audio AAC 256 kbps
#   1080p-const - Resize video (constant rate) to 1080p, audio AAC 256 kbps
#   720p - Resize video to 720p, audio AAC 192 kbps
#   720p-const - Resize video (constant rate) to 720p, audio AAC 192 kbps
#   480p - Resize video to 480p, audio AAC 128 kbps
#   480p-const - Resize video (constant rate) to 480p, audio AAC 128 kbps
#   360p - Resize video to 360p, audio AAC 128 kbps
#   360p-const - Resize video (constant rate) to 360p, audio AAC 128 kbps
#   <custom> - use your own ffmpeg options
#   Ex. "-vf scale=320:240"
# [path] Optional, defaults to current directory
#   Ex. ./Folder or ../Folder or "/Folder/SubFolder 2"
#
################################################################################

################################################################################
#
# USER OPTIONS
#
# Change properties inside function to tweak script behavior.
#
# [ffmpegPath] Path to ffmpeg location. If empty, will try to auto-detect 4.3+ version.
# [backupExtension] Backup extensions which will be added on original file.
# [log] Save logs to file, can be 1|0.
# [logPath] Log file path.
# [excludedFolders] Folder names where files won't be converted/reverted.
#
################################################################################

function setOptions() {
	ffmpegPath="ffmpeg"
	backupExtension="MP4cBAK"
	excludedFolders=("/tmp/" "/Recycler/" "/Recycled/" "/@Recycle/" "/\$Recycle.Bin/" "/@Transcode/" "/@DownloadStationTempFiles/" "/System Volume Information/" "/@Recently-Snapshot/" "/.@__thumb/" "/.@upload_cache/" "/#recycle/" "/@eaDir/" "/@tmp/")
	logActivated=1
	logPath="$(scriptPath)/mp4c.log"
}

################################################################################
#
# INPUTS
#
################################################################################

command="${1:-}"
extensions="${2:-}"
ffmpegOptions="${3:-copy}"
folderPath="${4:-.}"

################################################################################
#
# UTILITIES
#
################################################################################

function log() {
	local text="$1"
	local logMode="${2:-all}"    #all|echo|file
	local lineAction="${3:-new}" #new|append|replace
	local lineIndex="${4:-0}"    #<number>

	if [ "$logMode" == "all" ] || [ "$logMode" == "echo" ]; then
		printf "${text//%/%%}"
	fi
	if [ "$logActivated" == 1 ] && { [ "$logMode" == "all" ] || [ "$logMode" == "file" ]; }; then
		if [ "$lineAction" == "new" ]; then
			printf "${text//%/%%}" >>"$logPath"
			return
		fi

		text="$(echo "$text" | sed 's?/?\\/?g')"
		if [ "$lineAction" == "append" ] && [ "$lineIndex" -gt 0 ]; then
			sed -i "${lineIndex}s/^\(.*\)$/\1${text}/" "$logPath"
		elif [ "$lineAction" == "replace" ] && [ "$lineIndex" -gt 0 ]; then
			sed -i "${lineIndex}s/.*/${text}/" "$logPath"
		fi
	fi
}

function lowercase() {
	local text=$1

	echo "$(echo "$text" | tr "A-Z" "a-z")"
}

function joinArray() {
	local separator="$1"
	shift
	local arr=("$@")
	local text=$(printf "%s${separator}" "${arr[@]}")
	text="$(echo $text | sed "s/${separator}$//")"

	echo "$text"
}

function absolutePath() {
	local path=$1

	local pathFlag="$(cd "$path" 2>&1)"
	if [ -z "$pathFlag" ]; then
		path="$(
			cd $path
			pwd -P
		)"
	fi

	echo "$path"
}

function scriptPath() {
	local path="$(absolutePath "$(dirname "$0")")"

	echo "$path"
}

function includesAny() {
	local text="$1"
	shift
	local arr=("$@")
	local result=0

	for item in "${arr[@]}"; do
		if [[ "$text" == *"$item"* ]]; then
			result=1
			break
		fi
	done

	echo "$result"
}

function getLogFileLineCount() {
	local lineCount=0
	if [ "$logActivated" == 1 ]; then
		lineCount=$(wc -l <"$logPath")
	fi

	echo "$lineCount"
}

function stripFolderPath() {
	local fullPath=$1
	local filePath="$(echo "$fullPath" | sed "s?${folderPath}\(.*\)?\1?")"

	echo "$filePath"
}

function startTimer() {
	timeStart=$(date +%s)
}

function endTimer() {
	if [ "$timeStart" -gt 0 ]; then
		timeEnd=$(date +%s)
		timeDiff=$(date -ud "@$((timeEnd - timeStart))" +%T)
	fi
}

function resetTimer() {
	timeStart=0
	timeEnd=0
	timeDiff=0
}

function setError() {
	local message=$(echo "$1" | tr "\n" ";" | sed "s/.$//")
	isError=1

	if [ -n "$message" ]; then
		local lineOffset="${2:-0}"
		local filesLineIndex="$(($(getLogFileLineCount) + 1 + lineOffset))"
		local msg=$(log "|ERROR $message" "echo" "append" 1>&2)
		log "|ERROR $message" "file" "append" "$filesLineIndex"
	fi
}

function resetError() {
	isError=0
}

function setInputs() {
	isError=0
	files=()
	filesCount=0
	filesInProgressCount=0
	filesCompleteCount=0
	filesErrorCount=0
	timeStart=0
	timeEnd=0
	timeDiff=0
	ffmpegOptionsLabel=""

	cleanInputs
}

function cleanInputs() {
	if [ "$command" != "convert" ] && [ "$command" != "convert-replace" ]; then
		if [ "$ffmpegOptions" == "copy" ]; then
			folderPath="."
		else
			folderPath="$ffmpegOptions"
		fi
	fi

	folderPath="$(echo "$folderPath" | sed "s/\/$//")"
	folderPath="$(absolutePath "$folderPath")"
	ffmpegOptionsLabel="$ffmpegOptions"
	ffmpegOptions=($(echo "$(mapFfmpegOptions "$ffmpegOptions")" | tr " " "\n"))
	command="$(lowercase "$command")"

	if [ -z "$backupExtension" ]; then
		backupExtension="MP4cBAK"
	fi

	cleanExtensions
}

function cleanExtensions() {
	local cleanedExtensions=()
	local isArray="${extensions##*","*}"

	if [ -z "$isArray" ]; then
		extensions=($(echo $extensions | tr ',' "\n"))
		extensions=("${extensions[@]/#./}")
	else
		extensions=("$(echo "$extensions" | sed "s/^\.//")")
	fi

	for ((i = 0; i < ${#extensions[@]}; i++)); do
		if [ -n "${extensions[i]}" ]; then
			cleanedExtensions+=("$(lowercase ${extensions[$i]})")
		fi
	done

	extensions=("${cleanedExtensions[@]}")
}

function isFfmpegVersionValid() {
	local filePath="$1"
	local hasCorrectVersion=$(type "$filePath" 2>&1 >/dev/null)

	if [ -z "$hasCorrectVersion" ]; then
		hasCorrectVersion=1

		local targetVersion=42
		local currentVersion=$("$filePath" -version | sed -n "s/ffmpeg version \([0-9.]*\).*/\1/p")
		currentVersion="$(echo "$currentVersion" | sed "s/\.//g")"
		currentVersion="${currentVersion:0:2}"

		if [[ $currentVersion =~ ^[0-9]+$ ]] && [ "$currentVersion" -lt "$targetVersion" ]; then
			hasCorrectVersion=0
		fi
	else
		hasCorrectVersion=0
	fi

	echo "$hasCorrectVersion"
}
function setFfmpeg() {
	if [ -z "$ffmpegPath" ]; then
		ffmpegPath="ffmpeg"
	fi

	local qnapPackagePath="/opt/ffmpeg/ffmpeg"
	local synologyPackagePath="/usr/local/ffmpeg/bin/ffmpeg"
	local arr=("$ffmpegPath" "$qnapPackagePath" "$synologyPackagePath")

	ffmpegPath=""
	local isAvailable=0
	for item in "${arr[@]}"; do
		isAvailable=$(isFfmpegVersionValid "${item}")
		if [ "$isAvailable" -eq 1 ]; then
			ffmpegPath="$item"
			break
		fi
	done
}

function mapFfmpegOptions() {
	local inputOptions="$1"
	local videoEncoder="libx264"
	local audioEncoder="libfdk_aac"
	local mappedOptions="-map_metadata 0 -pix_fmt yuv420p"

	local isAudioEncoderAvailable="$("$ffmpegPath" -v quiet -encoders | grep "$audioEncoder")"
	if [ -z "$isAudioEncoderAvailable" ]; then
		audioEncoder="aac"
	fi

	case "$inputOptions" in
	copy)
		mappedOptions="$mappedOptions -c:v copy -c:a $audioEncoder -b:a 256k"
		;;
	1080p | 1080p-const)
		if [ -z "${inputOptions##*1080p-const*}" ]; then
			mappedOptions="$mappedOptions -b:v 4500k -minrate 4500k -maxrate 9000k -bufsize 9000k -preset slow"
		fi
		mappedOptions="$mappedOptions -c:v $videoEncoder -vf scale=iw*min(1\,if(gt(iw\,ih)\,1920/iw\,(1920*sar)/ih)):(floor((ow/dar)/2))*2 -c:a $audioEncoder -b:a 256k"
		;;
	720p | 720p-const)
		if [ -z "${inputOptions##*720p-const*}" ]; then
			mappedOptions="$mappedOptions -b:v 2500k -minrate 1500k -maxrate 4000k -bufsize 5000k -preset slow"
		fi
		mappedOptions="$mappedOptions -c:v $videoEncoder -vf scale=iw*min(1\,if(gt(iw\,ih)\,1280/iw\,(1280*sar)/ih)):(floor((ow/dar)/2))*2 -c:a $audioEncoder -b:a 192k"
		;;
	480p | 480p-const)
		if [ -z "${inputOptions##*480p-const*}" ]; then
			mappedOptions="$mappedOptions -b:v 1000k -minrate 500k -maxrate 2000k -bufsize 2000k -preset slow"
		fi
		mappedOptions="$mappedOptions -c:v $videoEncoder -vf scale=iw*min(1\,if(gt(iw\,ih)\,854/iw\,(854*sar)/ih)):(floor((ow/dar)/2))*2 -c:a $audioEncoder -b:a 128k"
		;;
	360p | 360p-const)
		if [ -z "${inputOptions##*360p-const*}" ]; then
			mappedOptions="$mappedOptions -b:v 750k -minrate 400k -maxrate 1000k -bufsize 1500k -preset slow"
		fi
		mappedOptions="$mappedOptions -c:v $videoEncoder -vf scale=iw*min(1\,if(gt(iw\,ih)\,640/iw\,(640*sar)/ih)):(floor((ow/dar)/2))*2 -c:a $audioEncoder -b:a 128k"
		;;
	*)
		mappedOptions="$inputOptions"
		;;
	esac

	echo "$mappedOptions"
}

function findAndSetFiles() {
	local path="$1"
	local pattern="$2"

	local data="$(find "$path/" -type f -iregex "$pattern" 2>&1)"
	local fileFlag="${data:0:1}"

	if [ -n "$fileFlag" ] && [ "$fileFlag" != "." ] && [ "$fileFlag" != "/" ]; then
		setError "$data" "-1"
		files=()
		return
	fi

	OIFS=$IFS
	IFS=$'\n'
	files=($data)
	IFS=$OIFS

	removeExcludedFromFiles
}

function removeExcludedFromFiles() {
	local cleanedFiles=()

	for ((i = 0; i < ${#files[@]}; i++)); do
		local containsExcludedFolder=$(includesAny "${files[i]}" "${excludedFolders[@]}")

		if [ "$containsExcludedFolder" == 0 ]; then
			cleanedFiles+=("${files[$i]}")
		fi
	done

	files=("${cleanedFiles[@]}")
}

function getExtensionFromBackupFile() {
	local filePath="$1"
	local extensionPattern="$(getExtensionsRegexPattern)"
	local fileExtension="$(echo $filePath | sed "s/\/.*${extensionPattern}\.${backupExtension}$/\1/i")"

	echo "${fileExtension/#./}"
}

function getExtensionsRegexPattern() {
	local extensionPattern=$(printf "\.%s\|" "${extensions[@]}")
	extensionPattern="$(echo $extensionPattern | sed 's/\\|$//')"
	extensionPattern="\($extensionPattern\)"

	echo "$extensionPattern"
}

function createBackupFile() {
	local sourceFilePath="$1"
	local backupFilePath="$sourceFilePath.$backupExtension"
	error=$(mv "$sourceFilePath" "$backupFilePath" 2>&1 >/dev/null)

	if [ -n "$error" ]; then
		setError "$error"
	fi
}

function revertBackupFile() {
	local backupFilePath="$1"
	local sourceFileExtension="$2"
	local originalFilePath="$(echo "$backupFilePath" | sed "s/\(.*\.${sourceFileExtension}\)\.${backupExtension}$/\1/i")"

	local error=$(mv "$backupFilePath" "$originalFilePath" 2>&1 >/dev/null)

	if [ -n "$error" ]; then
		setError "$error"
	fi

	if [ -f "$originalFilePath.mp4" ]; then
		rm "$originalFilePath.mp4"
	fi
}

function convertFileToMp4() {
	local sourceFilePath="$1"
	local destinationFolderPath="$(dirname "$sourceFilePath")"
	local destinationFileName="$(basename "$sourceFilePath").mp4"

	if [ "$command" == "convert-replace" ]; then
		destinationFileName="$(echo "$sourceFilePath" | sed "s/.*\/\(.*\).${backupExtension}$/\1/i").mp4"
	fi

	local mp4FilePath="$destinationFolderPath/$destinationFileName"
	local error=$("$ffmpegPath" -nostats -loglevel error -i "$sourceFilePath" -y "${ffmpegOptions[@]}" "$mp4FilePath" 2>&1 >/dev/null)

	if [ -z "$error" ]; then
		touch -r "$sourceFilePath" "$mp4FilePath"

		if [ "$command" == "convert" ]; then
			createBackupFile "$sourceFilePath"
		fi
	else
		setError "$error"
		if [ -f "$mp4FilePath" ]; then
			rm "$mp4FilePath"
		fi
	fi
}

function cleanMp4File() {
	local backupFilePath="$1"
	local sourceFileExtension="$2"
	local nameFilePath="$(echo "$backupFilePath" | sed "s/\(.*\)\.${sourceFileExtension}\.${backupExtension}$/\1/i")"
	local oldMp4FilePath="$nameFilePath.$sourceFileExtension.mp4"
	local cleanMp4FilePath="$nameFilePath.mp4"

	local uniqueMp4FileNameIndex=0
	if [ -f "$cleanMp4FilePath" ]; then
		uniqueMp4FileNameIndex=1
	fi
	while [ "$uniqueMp4FileNameIndex" -gt 0 ]; do
		if [ ! -f "$nameFilePath-$uniqueMp4FileNameIndex.mp4" ]; then
			cleanMp4FilePath="$nameFilePath-$uniqueMp4FileNameIndex.mp4"
			uniqueMp4FileNameIndex=0
		else
			uniqueMp4FileNameIndex=$((uniqueMp4FileNameIndex + 1))
		fi
	done

	local error=$(mv "$oldMp4FilePath" "$cleanMp4FilePath" 2>&1 >/dev/null)

	if [ -n "$error" ]; then
		setError "$error"
	fi

	if [ -f "$cleanMp4FilePath" ] && [ -f "$backupFilePath" ]; then
		rm "$backupFilePath"
	fi
}

################################################################################
#
# COMMANDS
#
################################################################################

function commandScan() {
	log "\n\n> Searching files..." "echo"

	findAndSetFiles "$folderPath" ".*$(getExtensionsRegexPattern)$"
	filesCount="${#files[@]}"

	local filesLineIndex="$(($(getLogFileLineCount) + 1))"
	log "FILES ${filesCount}" "file" "replace" "$filesLineIndex"
	log "\n" "file"

	log "\n> Found ${filesCount} file(s)\n" "echo"

	if [ "$filesCount" == 0 ]; then
		log "\n> Done" "echo"
		return
	fi

	for ((i = 0; i < filesCount; i++)); do
		local filePath="${files[i]}"
		local fileNumber=$((i + 1))

		log "  [${fileNumber}] $(stripFolderPath "$filePath")" "echo"
		log "$filePath" "file"

		if [ "$i" != "$((filesCount - 1))" ]; then
			log "\n"
		fi

		filesInProgressCount=$((filesInProgressCount + 1))
		filesCompleteCount=$((filesCompleteCount + 1))
	done

	log "\n> Done" "echo"
	log "\n" "file"
}

function commandConvert() {
	log "\n\n> Searching files..." "echo"

	local extensionPattern=".*$(getExtensionsRegexPattern)$"
	if [ "$command" == "convert-replace" ]; then
		extensionPattern=".*$(getExtensionsRegexPattern)\.${backupExtension}$"
	fi

	findAndSetFiles "$folderPath" "$extensionPattern"
	filesCount="${#files[@]}"

	local filesLineIndex="$(($(getLogFileLineCount) + 1))"
	log "FILES ${filesCount}" "file" "replace" "$filesLineIndex"
	log "\n" "file"

	log "\n> Found ${filesCount} file(s)" "echo"

	if [ "$filesCount" == 0 ]; then
		log "\n> Done" "echo"
		return
	fi

	log "\n> Processing files...\n" "echo"

	for ((i = 0; i < filesCount; i++)); do
		local filePath="${files[i]}"
		local fileNumber=$((i + 1))

		log "  [${fileNumber}] $(stripFolderPath "$filePath")" "echo"
		log "$filePath" "file"
		filesInProgressCount=$((filesInProgressCount + 1))

		convertFileToMp4 "$filePath"

		log "\n"

		if [ "$isError" == 0 ]; then
			filesCompleteCount=$((filesCompleteCount + 1))
		else
			filesErrorCount=$((filesErrorCount + 1))
		fi

		resetError
	done

	log "> Done $filesCompleteCount/$filesCount (success/total)" "echo"
}

function commandRevert() {
	log "\n\n> Searching files..." "echo"

	findAndSetFiles "$folderPath" ".*$(getExtensionsRegexPattern)\.${backupExtension}$"
	filesCount="${#files[@]}"

	local filesLineIndex="$(($(getLogFileLineCount) + 1))"
	log "FILES ${filesCount}" "file" "replace" "$filesLineIndex"
	log "\n" "file"

	log "\n> Found ${filesCount} file(s)" "echo"

	if [ "$filesCount" == 0 ]; then
		log "\n> Done" "echo"
		return
	fi

	log "\n> Processing files...\n" "echo"

	for ((i = 0; i < filesCount; i++)); do
		local filePath="${files[i]}"
		local fileExtension="$(getExtensionFromBackupFile "$filePath")"
		local fileNumber=$((i + 1))

		log "  [${fileNumber}] $(stripFolderPath "$filePath")" "echo"
		log "$filePath" "file"
		filesInProgressCount=$((filesInProgressCount + 1))

		revertBackupFile "$filePath" "$fileExtension"

		log "\n"

		if [ "$isError" == 0 ]; then
			filesCompleteCount=$((filesCompleteCount + 1))
		else
			filesErrorCount=$((filesErrorCount + 1))
		fi

		resetError
	done

	log "> Done $filesCompleteCount/$filesCount (success/total)" "echo"
}

function commandClean() {
	log "\n\n> Searching files..." "echo"

	findAndSetFiles "$folderPath" ".*$(getExtensionsRegexPattern)\.${backupExtension}$"
	filesCount="${#files[@]}"

	local filesLineIndex="$(($(getLogFileLineCount) + 1))"
	log "FILES ${filesCount}" "file" "replace" "$filesLineIndex"
	log "\n" "file"

	log "\n> Found ${filesCount} file(s)" "echo"

	if [ "$filesCount" == 0 ]; then
		log "\n> Done" "echo"
		return
	fi

	log "\n> Processing files...\n" "echo"

	for ((i = 0; i < filesCount; i++)); do
		local filePath="${files[i]}"
		local fileExtension="$(getExtensionFromBackupFile "$filePath")"
		local fileNumber=$((i + 1))

		log "  [${fileNumber}] $(stripFolderPath "$filePath")" "echo"
		log "$filePath" "file"
		filesInProgressCount=$((filesInProgressCount + 1))

		cleanMp4File "$filePath" "$fileExtension"

		log "\n"

		if [ "$isError" == 0 ]; then
			filesCompleteCount=$((filesCompleteCount + 1))
		else
			filesErrorCount=$((filesErrorCount + 1))
		fi

		resetError
	done

	log "> Done $filesCompleteCount/$filesCount (success/total)" "echo"
}

function commandInvalid() {
	isError=1

	log "\n\n> ERROR Invalid command" "echo"
	log "\n> Done" "echo"

	local logLineCount="$(getLogFileLineCount)"
	local lineOffset=2
	local targetLine=$((logLineCount - filesInProgressCount - lineOffset))
	log "|ERROR invalid command" "file" "append" "$targetLine"
	log "\n" "file"
}

################################################################################
#
# HOOKS
#
################################################################################

function earlyExit() {
	log "\n> Interrupted" "echo"
	log "\n" "file"
	afterStatus
	exit
}

function beforeStatus() {
	startTimer

	log "\nMP4 Converter\n" "echo"
	local startDateTime="$(date -d @$timeStart +%F_%T)"
	log "#" "file"
	log "\nDATE ${startDateTime}" "file"
	log "\nSTATUS" "file"
	log "\nCOMMAND $command"
	local extensionsText="$(joinArray "," "${extensions[@]}")"
	log "\nEXTENSIONS $extensionsText"
	if [ "$command" == "convert" ] || [ "$command" == "convert-replace" ]; then
		log "\nOPTIONS $ffmpegOptionsLabel"
	else
		log "\nOPTIONS " "file"
	fi
	log "\nFOLDER ${folderPath}"
	log "\nFILES ${filesCount}" "file"
}

function afterStatus() {
	endTimer

	log "\n\nTIME $timeDiff (hh:mm:ss)\n\n" "echo"

	local logLineCount="$(getLogFileLineCount)"
	local lineOffset=6
	local targetLine=$((logLineCount - filesInProgressCount - lineOffset))

	local endDateTime="$(date -d @$timeEnd +%F_%T)"
	log "__$endDateTime" "file" "append" "$targetLine"
	resetTimer

	lineOffset=5
	targetLine=$((logLineCount - filesInProgressCount - lineOffset))

	if [ "$filesCount" -gt 0 ] && [ "$filesCount" == "$filesCompleteCount" ]; then
		log " success" "file" "append" "$targetLine"
	elif [ "$isError" == 1 ] || [ "$filesErrorCount" -gt 0 ]; then
		log " error" "file" "append" "$targetLine"
	elif [ "$filesInProgressCount" == 0 ]; then
		log " skip" "file" "append" "$targetLine"
	else
		log " interrupt" "file" "append" "$targetLine"
	fi

	local targetLine=$((logLineCount - filesCount))
	if [ "$filesErrorCount" -gt 0 ]; then
		log "|ERROR $filesErrorCount" "file" "append" "$targetLine"
	fi
}

################################################################################
#
# MESSAGES
#
################################################################################

function ffmpegMissingMessage() {

	message="
MP4 Converter - ERROR ffmpeg

> ffmpeg 4.3+ is minimum requirement, make sure you have it installed!
  To set correct path of your ffmpeg, change \"ffmpegPath\" under
  User Options of this script.

"

	log "$message" "echo"
}

function helpMessage() {

	message="
MP4 Converter - HELP

> sh mp4c.sh [command] [extensions] [*ffmpegOptions] [path]

[command] Required
  scan - Find video files
  convert - Convert video files to mp4 and create backups
  convert-replace - Replace already converted files with new
  revert - Revert original files (if backups exists)
  clean - Clean and keep .mp4 files, remove backups
[extensions] Required, one or more (separated with comma)
  Ex. mts or MTS or .mts,.mov
[*ffmpegOptions] Optional, used ONLY with convert and convert-replace command, defaults to copy
  copy - Preserve video, audio AAC 256 kbps
  1080p - Resize video to 1080p, audio AAC 256 kbps
  1080p-const - Resize video (constant rate) to 1080p, audio AAC 256 kbps
  720p - Resize video to 720p, audio AAC 192 kbps
  720p-const - Resize video (constant rate) to 720p, audio AAC 192 kbps
  480p - Resize video to 480p, audio AAC 128 kbps
  480p-const - Resize video (constant rate) to 480p, audio AAC 128 kbps
  360p - Resize video to 360p, audio AAC 128 kbps
  360p-const - Resize video (constant rate) to 360p, audio AAC 128 kbps
  <custom> - use your own ffmpeg options
  Ex. 480p or \"-vf scale=320:240\"
[path] Optional, defaults to current directory
  Ex. ./Folder or ../Folder or \"/Folder/SubFolder 2\"

"

	log "$message" "echo"
}

################################################################################
#
# MAIN
#
################################################################################

function main() {
	setOptions
	setFfmpeg

	if [ -z "$ffmpegPath" ]; then
		ffmpegMissingMessage
		return
	fi

	setInputs

	if [ -z "$command" ] || [ "${#extensions[@]}" -lt 1 ]; then
		helpMessage
		return
	fi

	beforeStatus

	trap earlyExit SIGINT SIGTERM

	case "$command" in
	convert | convert-replace)
		commandConvert
		;;
	revert)
		commandRevert
		;;
	clean)
		commandClean
		;;
	scan)
		commandScan
		;;
	*)
		commandInvalid
		;;
	esac

	afterStatus
}

main
