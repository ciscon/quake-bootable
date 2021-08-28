#!/bin/bash

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$scriptdir"

current_preset=$(basename $(readlink -f qw))
declare -a qwdirs

echo "Available presets:"

count=1
for qw in "$scriptdir/qw."* ;do
	qwdirs[$count]=$(basename $qw)
	if [ "${qwdirs[$count]}" = "$current_preset" ];then
		current="(currently selected)"
	else
		current=""
	fi
	qw=${qw##*.}
	echo "$count) $qw $current"
	let count=count+1
done

read -p 'Choose asset preset: ' option
if [ ${qwdirs[$option]+asdf} ];then
	qw=${qwdirs[$option]}
	qwclean=${qw##*.}
	echo "Setting preset to '$qwclean'"
	rm -f qw
	ln -sf $qw qw
else
	echo "Option invalid, exiting."
	exit 1
fi
echo "Complete."
