#!/bin/bash

function ffmpeg-concatenate-videos ()
{
    file_list_file=$(mktemp ./ffmpeg_file_list.XXXXXXXXX)

    for ((i=2;i<=$#;i++))
    do
        echo "file '${!i}'" >> "$file_list_file"
    done

    output_file_name="$1.mkv"

    video_codec="h264"
    audio_codec="flac"

    #    video_codec="copy"
    #    audio_codec="copy"

    ffmpeg -f concat \
        -safe 0 \
        -i "$file_list_file" \
        -map_metadata 0 \
        -map_chapters 0 \
        -acodec $audio_codec \
        -vcodec $video_codec \
        -scodec copy \
        "$output_file_name"

    rm -f "$file_list_file"
}

function ffmpeg-video-split-by-timestamps ()
{
    file="$1"
    if [ -z "$file" ]; then
        echo "Missing file argument!"
        exit 1
    fi

    #    video_codec="$(ffprobe -loglevel error -select_streams v:0 -show_entries stream=codec_name -of default=nk=1:nw=1 "$1.mkv")"
    #    audio_codec="$(ffprobe -loglevel error -select_streams a:0 -show_entries stream=codec_name -of default=nk=1:nw=1 "$1.mkv")"
    #    subtitle_codec="$(ffprobe -loglevel error -select_streams s:0 -show_entries stream=codec_name -of default=nk=1:nw=1 "$1.mkv")"

    #    video_codec="h264"
    #    audio_codec="flac"
    #    subtitle_codec="$(ffprobe -loglevel error -select_streams s:0 -show_entries stream=codec_name -of default=nk=1:nw=1 "$1.mkv")"

    video_codec="copy"
    audio_codec="copy"
    subtitle_codec="copy"

    filename=$(basename "$file")
    filename="${filename%.*}"

    if [[ "$3" ]]; then
        k=1
        j=2

        for ((i=3;i<=$#;i++))
        do
            # shellcheck disable=SC2027 # This is actually what we want
            output_file_name=$filename"_split"$(printf '_%03s' $k)".mkv"

            echo ${!j} "${!i}" "$output_file_name"

            ffmpeg -y -i "$1" \
                -ss ${!j} -to "${!i}" \
                -map 0:v \
                -vcodec $video_codec \
                -map 0:a \
                -acodec $audio_codec \
                -map 0:s? \
                -scodec $subtitle_codec \
                "$output_file_name" &

            if [[ $((k%3)) -eq 0 ]]; then
                wait
            fi

            k=$((k+1))
            j=$((j+1))
        done
    else
        output_file_name=$filename"_split_001.mkv"
        end_timestamp=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file")

        echo "$end_timestamp"

        ffmpeg -y -i "$1" \
            -ss "$2" -to "$end_timestamp" \
            -map 0:v \
            -vcodec $video_codec \
            -map 0:a \
            -acodec $audio_codec \
            -map 0:s? \
            -scodec $subtitle_codec \
            "$output_file_name" &
    fi
    wait
}
function ffmpeg-video-split-by-chapters ()
{
    file="$1"
    if [ -z "$file" ]; then
        echo "Missing file argument!"
        exit 1
    fi

    # shellcheck disable=SC2207 # Don't want to rework it yet
    timestamp_list=($(ffprobe -i "$file" -show_chapters -loglevel error | grep end_time | cut -d '=' -f 2 ))

    ffmpeg_command="ffmpeg-video-split-by-timestamps $file 0.00 "
    for i in "${timestamp_list[@]}";
    do
        ffmpeg_command=$ffmpeg_command"$i "
    done

    echo "$ffmpeg_command"
    eval "$ffmpeg_command"
}

function ffmpeg-video-merge-chapters ()
{
    base_command='ffmpeg-concatenate-videos '
    file_extension='.mkv '
    base_file=$1
    chapters_per_episode=$2
    total_chapters=$3

    total_episodes=$total_chapters/$chapters_per_episode

    chapter=1
    for ((episode=1;episode<=total_episodes;episode++))
    do
        file_list=""
        for ((i=1;i<=chapters_per_episode;i++))
        do
            file_list=$file_list$base_file"_split"$(printf '_%03s' $chapter)$file_extension
            chapter=$((chapter+1))
        done
        ffmpeg_command=$base_command$base_file$(printf '_e%03d ' "$episode")$file_list
        echo "$ffmpeg_command"
        eval "$ffmpeg_command"
    done

}

function ffmpeg-video-crop-encode ()
{
    if [ -z "$1" ]; then
        python -I ~/dot-files/scripts/ffmpeg.py video-crop-encode
    else
        python -I ~/dot-files/scripts/ffmpeg.py video-crop-encode --input_filename="$1"
    fi
}

function ffmpeg-video-make-dvd ()
{
    if [ -z "$1" ]; then
        python -I ~/dot-files/scripts/ffmpeg.py make-dvd
    else
        python -I ~/dot-files/scripts/ffmpeg.py make-dvd --input_filename="$1"
    fi
}

function ffmpeg-audio-split-encode ()
{
    if [ -z "$1" ]; then
        python -I ~/dot-files/scripts/ffmpeg.py audio-split-encode
    else
        python -I ~/dot-files/scripts/ffmpeg.py audio-split-encode --input_filename="$1"
    fi
}

#ffmpeg-video-split-by-timestamps Pokemon_Master_Quest_D1_t00 00:00:00 00:41:09 01:20:41
#ffmpeg-video-split-by-chapters Pokemon_Master_Quest_D7_t00.mkv
#ffmpeg-video-merge-chapters Pokemon_Master_Quest_D1_t00 4 36

function ffmpeg-audio-convert ()
{
    local search_dir="${1:-.}"  # Default to current directory if no argument provided

    # Check if ffmpeg is installed
    if ! command -v ffmpeg &> /dev/null
    then
        echo "ffmpeg could not be found. Please install ffmpeg first."
        return 1
    fi

    # Find all audio files and store them in an array
    mapfile -t audio_files < <(find "$search_dir" -type f \( -iname "*.mp3" -o -iname "*.wav" -o -iname "*.aac" -o -iname "*.m4a" -o -iname "*.ogg" \))

    for file in "${audio_files[@]}"; do
        # Get the directory path and filename without extension
        dir_path=$(dirname "$file")
        base_name=$(basename "$file")
        new_name="${base_name%.*}.flac"

        # Convert the file to FLAC
        ffmpeg -i "$file" -c:a flac -compression_level 12 -map_metadata 0 "$dir_path/$new_name"

        # Check if conversion was successful
        if [ $? -eq 0 ]; then
            echo "Converted $file to $dir_path/$new_name"

            # Preserve Windows file metadata
            touch -r "$file" "$new_name"  # Copies modification times
            cp -a "$file" "$new_name"     # Copies all file attributes (permissions, timestamps)

            # Create an archives directory if it doesn't exist
            mkdir -p "archives/$dir_path"

            # Move the original file to the archives directory
            mv --verbose "$file" "archives/$dir_path"
            echo "Moved original file to archives/$dir_path"
        else
            echo "Failed to convert $file"
        fi
    done
}


# for file in *.mp3; do
#     # Extract the middle part of the filename excluding "Day X" at the start and "YYYY" at the end
#     new_name=$(echo "$file" | sed -r 's/^([0-9]{4}-[0-9]{2}-[0-9]{2})-Day [0-9]+ (.*) (\([0-9]{4}\)|[0-9]{4})\.mp3$/\1 - \2.mp3/')

#     # Rename the file if the new name is different from the original
#     if [ "$file" != "$new_name" ]; then
#         mv "$file" "$new_name"
#         echo "Renamed: $file to $new_name"
#     fi
# done



# mv '2021-12-28-BONUS  Bringing the Bible Back to Catholics (with Jeff Cavins)- 2022.mp3'                                    '2021-12-28-0-Bringing the Bible Back to Catholics.mp3'
# mv '2021-12-30-BONUS  How to Hear God'\''s Voice in Scripture (2022).mp3'                                                   '2021-12-30-0-How to Hear God'\''s Voice in Scripture.mp3'
# mv '2022-01-01-START HERE  Introduction to the Early World (with Jeff Cavins) - 2022.mp3'                                   '2022-01-01-0-Introduction to the Early World.mp3'
# mv '2022-01-06-Introduction to the Patriarchs (with Jeff Cavins) - 2022.mp3'                                                '2022-01-06-0-Introduction to the Patriarchs.mp3'
# mv '2022-01-27-Introduction to Egypt & Exodus (with Jeff Cavins) - 2022.mp3'                                                '2022-01-27-0-Introduction to Egypt & Exodus.mp3'
# mv '2022-02-21-Introduction to Desert Wanderings (with Jeff Cavins) - 2022.mp3'                                             '2022-02-21-0-Introduction to Desert Wanderings.mp3'
# mv '2022-03-22-Introduction to Conquest & Judges (with Jeff Cavins) - 2022.mp3'                                             '2022-03-22-0-Introduction to Conquest & Judges.mp3'
# mv '2022-04-09-Messianic Checkpoint  The Gospel of John (with Jeff Cavins) - 2022.mp3'                                      '2022-04-09-0-Messianic Checkpoint  The Gospel of John.mp3'
# mv '2022-04-16-Introduction to the Royal Kingdom (with Jeff Cavins) - 2022.mp3'                                             '2022-04-16-0-Introduction to the Royal Kingdom.mp3'
# mv '2022-06-03-Messianic Checkpoint  The Gospel of Mark (with Jeff Cavins) - 2022.mp3'                                      '2022-06-03-0-Messianic Checkpoint  The Gospel of Mark.mp3'
# mv '2022-07-03-Introduction to the Exile (with Jeff Cavins) - 2022.mp3'                                                     '2022-07-03-0-Introduction to the Exile.mp3'
# mv '2022-09-15-Messianic Checkpoint  The Gospel of Matthew (with Jeff Cavins) - 2022.mp3'                                   '2022-09-15-0-Messianic Checkpoint  The Gospel of Matthew.mp3'
# mv '2022-09-24-BONUS  If You Feel Like Giving Up (with Jeff Cavins) - 2022.mp3'                                             '2022-09-24-0-If You Feel Like Giving Up.mp3'
# mv '2022-09-24-Introduction to the Return (with Jeff Cavins) - 2022.mp3'                                                    '2022-09-24-0-Introduction to the Return.mp3'
# mv '2022-10-09-Introduction to the Maccabean Revolt (with Jeff Cavins) - 2022.mp3'                                          '2022-10-09-0-Introduction to the Maccabean Revolt.mp3'
# mv '2022-11-09-Messianic Checkpoint  The Gospel of Luke (with Jeff Cavins) - 2022.mp3'                                      '2022-11-09-0-Messianic Checkpoint  The Gospel of Luke.mp3'
# mv '2022-11-18-Introduction to the Church (with Jeff Cavins) - 2022.mp3'                                                    '2022-11-18-0-Introduction to the Church.mp3'
# mv '2022-12-28-BONUS  Preparing for the Bible in a Year Journey (2023).mp3'                                                 '2022-12-28-0-Preparing for the Bible in a Year Journey.mp3'
# mv '2022-12-29-BONUS  Catholics and the Bible (with Jeff Cavins) 2023.mp3'                                                  '2022-12-29-0-Catholics and the Bible.mp3'

# for file in *; do
#     # Get the new filename by converting to lowercase, replacing spaces with hyphens,
#     # and then reducing multiple consecutive hyphens to a single hyphen
#     new_name=$(echo "$file" | tr 'A-Z' 'a-z' | tr ' ' '-' | sed 's/-*-/-/g')

#     # Rename the file if the new name is different from the original
#     if [ "$file" != "$new_name" ]; then
#         mv "$file" "$new_name"
#     fi
# done
