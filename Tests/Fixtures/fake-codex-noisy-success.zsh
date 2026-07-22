#!/bin/zsh
set -u

IFS= read -r initialize_request || exit 1
[[ $initialize_request == *'"id":1'*'"method":"initialize"'* ]] || exit 2
[[ $initialize_request != *'"experimentalApi"'* ]] || exit 3
print -r -- '{"id":999,"error":{"message":"Unrelated request failed"}}'
print -r -- '{"id":"1","result":{}}'

IFS= read -r initialized_notification || exit 1
[[ $initialized_notification == '{"method":"initialized"}' ]] || exit 4

IFS= read -r rate_limits_request || exit 1
[[ $rate_limits_request == *'"id":2'*'account'*'rateLimits'*'read'* ]] || exit 5
print -r -- '{"id":998,"error":{"message":"Another request failed"}}'
print -r -- '{"id":"2","result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":1786000000}}}}'

while IFS= read -r _; do :; done
