#!/bin/zsh
set -u

fail_protocol() {
  print -r -- '{"id":1,"error":{"message":"Unexpected client protocol sequence"}}'
  while IFS= read -r _; do :; done
  exit 1
}

IFS= read -r initialize_request || exit 1
[[ $initialize_request == *'"id":1'*'"method":"initialize"'* ]] || fail_protocol
[[ $initialize_request != *'"experimentalApi"'* ]] || fail_protocol
print -r -- '{"id":1,"result":{}}'

IFS= read -r initialized_notification || exit 1
[[ $initialized_notification == '{"method":"initialized"}' ]] || fail_protocol

IFS= read -r rate_limits_request || exit 1
[[ $rate_limits_request == *'"id":2'*'account'*'rateLimits'*'read'* ]] || fail_protocol
print -r -- '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":1785510000},"secondary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":1786000000}}}}'

while IFS= read -r _; do :; done
