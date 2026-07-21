#!/bin/zsh
set -u

IFS= read -r _ || exit 1
while IFS= read -r _; do :; done
