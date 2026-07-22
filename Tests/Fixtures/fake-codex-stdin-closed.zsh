#!/bin/zsh
set -u

IFS= read -r initialize_request || exit 1
[[ $initialize_request == *'"id":1'*'"method":"initialize"'* ]] || exit 2
exec 0<&-
print -r -- '{"id":1,"result":{}}'

while :; do sleep 1; done
