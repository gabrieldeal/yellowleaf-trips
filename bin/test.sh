#!/bin/sh
input="$1"
temp="$1.temp"
perl -p -e 's/\r*\n/\r\n/' < $input > $temp; mv $temp $input