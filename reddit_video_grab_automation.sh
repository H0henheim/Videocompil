#!/bin/bash
#
# Downloads ten videos from /r/<subreddit>, concatenates every video file with blur box effect
# using h264_libx264 encoder (CPU rendering)
# 

date=$(date +%Y-%m-%d_%H:%M:%S)
subreddit="subreddit.txt"
title_url="title_url.txt"
dl_dir="dl"
blur_dir="blur"
title_dir="title"
rendered_dir="rendered"

mkdir -p $dl_dir $blur_dir $rendered_dir $title_dir

#
# TODO
# Narrow title down
# Log events
#

# parallel download videos from /r/$subreddit
function get_video () {
echo "" > $3
grep -v '^#' $1 | while read line
do
	curl -s -H "User-agent: 'Somebody 0.2'" https://www.reddit.com/r/$line/search.json?limit=10\&q=url:v.redd.it\&restrict_sr=on\&sort=hot | jq -r '.data.children[].data | .title + " | " + .url_overridden_by_dest + " | " + (.media.reddit_video.duration|tostring) // empty' \
	| xargs -I '{}' echo '{}' >> $3

awk -F"|" '$3 < 30' $3 | awk -F"|" '{print $2}' \
| xargs -I '{}' -P 5 python3 /usr/local/bin/youtube-dl --no-continue -o $2'/%(title)s.%(ext)s' '{}'
done
}


# remove space in filename because of ffmpeg
function remove_space () { 
find $1 -type f -name "* *" | while read file; do mv "$file" ${file// /_}; done
}

# convert all video in mp4
function convert_in_mp4 () {
for f in $1/*; do
if [[ $(file --mime-type -b $f) != "video/mp4" ]];
then
ffmpeg -n -i $f -preset fast ${f%.*}.mp4 ;
rm -f $f
fi
done
}

function add_title_overlay () {
for f in $1/*.mp4; do
id=$(echo $f | cut -d'.' -f1 | cut -d '/' -f2)
title=$(grep $id $3 | cut -d'|' -f1)
ffmpeg -i $f -vf \
"format=yuv444p, \
 drawbox=y=ih-ih/5:color=black@0.4:width=iw:height=24:t=fill, \
 drawtext=fontfile=OpenSans-Regular.ttf:text='$title':fontcolor=white:fontsize=12:x=(w-tw)/2:y=(h-h/5)+th, \
format=yuv420p" \
 -c:v libx264 -crf 9 -preset slow -c:a copy $2/$(echo $f | cut -d'/' -f2)
done
}

# add blur box, aspect ratio 16/9
function ratio_and_blur () {
for f in $1/*.mp4; do 
ffmpeg -n -hide_banner -i $f \
 -vf 'split[original][copy];[copy]scale=ih*16/9:-1,crop=h=iw*9/16,gblur=sigma=20[blurred];[blurred][original]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2' \
 -c:v h264_nvenc -r 30 -preset fast $2/$(echo $f | cut -d'/' -f2);
done
}

# remove empty mp4 file when ratio_and_blur fails 
function remove_if_empty () {
for f in $1/*.mp4; do
if ! [ -s $f ] # if not file is not empty 
then
rm -f $f ;
fi
done
}

# Generate file list
function generate_file_list () {
local trans_file="file 'fx/transition.mp4'"
local open_file="file 'fx/turn_on.mp4'"
local end_file="file 'fx/tv_no_signal_corrected.mp4'"

printf "file '%s'\n" $1/*.mp4 > file_list.txt
sed "/title\/.*/a $trans_file" -i file_list.txt # insert transition after each line containing blur word
#sed "$ d" -i file_list.txt # suppress last transition to insert turn_off video
echo -e "$open_file\n$(cat file_list.txt)" > file_list.txt # insert turn_on at beginning
echo $end_file >> file_list.txt # append turn_off
}

# Final render
function final_render () {
ffmpeg -f concat -safe 0 -i $1 -c:v libx264 -r 30 -preset fast $2/output\_$date.m4v
#ffmpeg -f concat -i file_list.txt -c:v h264_nvenc -r 30 -preset fast rendered/$subreddit\_$date.m4v
}

# cleanup
function cleanup () {
rm -f $1/*.{mp4,webm,mkv} $2/*.{mp4,webm,mkv} $3/*.mp4
}

# upload to youtube
#python2 $HOME/bw/.local/bin/upload.py --file="final.mp4" --title="$subreddit Compilation" --description="Buy my merchandise - spamlink.ly" --keywords="tiktok,cringe" --category="22" --privacyStatus="public"

cleanup $dl_dir $blur_dir $title_dir
get_video $subreddit $dl_dir $title_url
remove_space $dl_dir
convert_in_mp4 $dl_dir
ratio_and_blur $dl_dir $blur_dir
remove_if_empty $blur_dir
add_title_overlay $blur_dir $title_dir $title_url
generate_file_list $title_dir
final_render "file_list.txt" $rendered_dir
cleanup $dl_dir $blur_dir $title_dir

