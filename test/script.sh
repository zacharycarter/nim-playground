#!/bin/bash

file=$1
compilationTarget=$2

exec  1> $"/usercode/logfile.txt"
exec  2> $"/usercode/errors.txt"
exec  < /dev/null

chmod 777 /usercode/logfile.txt
chmod 777 /usercode/errors.txt

nim c++ /usercode/$file
if [ $? -eq 0 ];	then
    ./usercode/${file/.nim/""}
else
    echo "Compilation Failed"
fi
