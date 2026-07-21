#!/bin/zsh
set -u

IFS= read -r _ || exit 1
print -r -- '{"id":1,"error":{"message":"  Sign in\nrequired\t "}}'
while IFS= read -r _; do :; done
