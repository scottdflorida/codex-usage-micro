#!/bin/zsh
set -u

IFS= read -r initialize_request || exit 1
[[ $initialize_request == *'"id":1'*'"method":"initialize"'* ]] || exit 2
print -u2 -r -- 'fatal startup failure'
exit 23
