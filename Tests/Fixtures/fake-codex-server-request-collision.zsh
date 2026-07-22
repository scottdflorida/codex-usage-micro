#!/bin/zsh
set -u

IFS= read -r initialize_request || exit 1
[[ $initialize_request == *'"id":1'*'"method":"initialize"'* ]] || exit 2
print -r -- '{"id":1,"method":"loginChatGpt/confirm","params":{}}'
print -r -- '{"id":1,"result":{}}'

IFS= read -r initialized_notification || exit 1
[[ $initialized_notification == '{"method":"initialized"}' ]] || exit 3

IFS= read -r rate_limits_request || exit 1
[[ $rate_limits_request == *'"id":2'*'account'*'rateLimits'*'read'* ]] || exit 4
print -r -- '{"id":2,"method":"account/updated","params":{"usedPercent":99}}'
print -r -- '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":1786000000}}}}'

while IFS= read -r _; do :; done
