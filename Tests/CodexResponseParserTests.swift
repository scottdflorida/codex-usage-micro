import Foundation

func codexResponseParserTests() -> [TestCase] {
    let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)

    func parse(_ json: String) throws -> UsageReport {
        try CodexResponseParser.parseRateLimitsResponse(Data(json.utf8), now: referenceNow)
    }

    return [
        TestCase(name: "named Codex bucket is parsed") {
            let report = try parse(
                """
                {"id":2,"result":{
                  "rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":60,"resetsAt":10}},
                  "rateLimitsByLimitId":{"codex":{"primary":{
                    "usedPercent":32,"windowDurationMins":10080,"resetsAt":1700000000
                  }}}
                }}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 32)
            try expectEqual(report.weekly?.windowDurationMinutes, 10_080)
            try expectEqual(report.weekly?.resetsAt, Date(timeIntervalSince1970: 1_700_000_000))
            try expectEqual(report.fiveHour, nil)
        },
        TestCase(name: "legacy bucket is supported") {
            let report = try parse(
                #"{"result":{"rateLimits":{"primary":{"usedPercent":41,"windowDurationMins":10080,"resetsAt":1700000100}}}}"#
            )
            try expectEqual(report.weekly?.usedPercent, 41)
            try expectEqual(report.fiveHour, nil)
        },
        TestCase(name: "weekly secondary is selected from a dual-window response") {
            let report = try parse(
                """
                {"result":{"rateLimitsByLimitId":{"codex":{
                  "primary":{"usedPercent":72,"windowDurationMins":300,"resetsAt":1700001000},
                  "secondary":{"usedPercent":28,"windowDurationMins":10080,"resetsAt":1700600000}
                }}}}
                """
            )
            try expectEqual(report.fiveHour?.usedPercent, 72)
            try expectEqual(report.fiveHour?.windowDurationMinutes, 300)
            try expectEqual(report.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_700_001_000))
            try expectEqual(report.weekly?.usedPercent, 28)
            try expectEqual(report.weekly?.windowDurationMinutes, 10_080)
            try expectEqual(report.weekly?.resetsAt, Date(timeIntervalSince1970: 1_700_600_000))
        },
        TestCase(name: "window meaning does not depend on primary ordering") {
            let report = try parse(
                """
                {"result":{"rateLimitsByLimitId":{"codex":{
                  "primary":{"usedPercent":28,"windowDurationMins":10080,"resetsAt":1700600000},
                  "secondary":{"usedPercent":72,"windowDurationMins":300,"resetsAt":1700001000}
                }}}}
                """
            )
            try expectEqual(report.fiveHour?.usedPercent, 72)
            try expectEqual(report.weekly?.usedPercent, 28)
        },
        TestCase(name: "weekly primary is accepted without a secondary") {
            let report = try parse(
                """
                {"result":{"rateLimits":{
                  "primary":{"usedPercent":19,"windowDurationMins":10080,"resetsAt":1700500000},
                  "secondary":null
                }}}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 19)
            try expectEqual(report.weekly?.windowDurationMinutes, 10_080)
            try expectEqual(report.fiveHour, nil)
        },
        TestCase(name: "weekly secondary is accepted without a five-hour window") {
            let report = try parse(
                """
                {"result":{"rateLimits":{
                  "primary":null,
                  "secondary":{"usedPercent":24,"windowDurationMins":10080,"resetsAt":1700500000}
                }}}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 24)
            try expectEqual(report.fiveHour, nil)
        },
        TestCase(name: "incomplete named bucket falls back to legacy") {
            let report = try parse(
                """
                {"result":{
                  "rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1700000200}},
                  "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":99}}}
                }}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 12)
        },
        TestCase(name: "optional five-hour window falls back independently to legacy data") {
            let report = try parse(
                """
                {"result":{
                  "rateLimits":{"primary":{"usedPercent":44,"windowDurationMins":300,"resetsAt":1700001000}},
                  "rateLimitsByLimitId":{"codex":{"primary":{
                    "usedPercent":18,"windowDurationMins":10080,"resetsAt":1700002000
                  }}}
                }}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 18)
            try expectEqual(report.fiveHour?.usedPercent, 44)
        },
        TestCase(name: "named weekly bucket wins an equal-duration conflict") {
            let report = try parse(
                """
                {"result":{
                  "rateLimits":{"primary":{"usedPercent":88,"windowDurationMins":10080,"resetsAt":1700001000}},
                  "rateLimitsByLimitId":{"codex":{"primary":{
                    "usedPercent":22,"windowDurationMins":10080,"resetsAt":1700002000
                  }}}
                }}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 22)
        },
        TestCase(name: "named five-hour bucket wins an equal-duration conflict") {
            let report = try parse(
                """
                {"result":{
                  "rateLimits":{
                    "primary":{"usedPercent":88,"windowDurationMins":300,"resetsAt":1700001000},
                    "secondary":{"usedPercent":35,"windowDurationMins":10080,"resetsAt":1700002000}
                  },
                  "rateLimitsByLimitId":{"codex":{
                    "primary":{"usedPercent":22,"windowDurationMins":300,"resetsAt":1700002000},
                    "secondary":{"usedPercent":31,"windowDurationMins":10080,"resetsAt":1700003000}
                  }}
                }}
                """
            )
            try expectEqual(report.fiveHour?.usedPercent, 22)
            try expectEqual(report.weekly?.usedPercent, 31)
        },
        TestCase(name: "a future longer window does not masquerade as weekly") {
            let report = try parse(
                """
                {"result":{"rateLimitsByLimitId":{"codex":{
                  "primary":{"usedPercent":91,"windowDurationMins":20160,"resetsAt":1700001000},
                  "secondary":{"usedPercent":31,"windowDurationMins":10080,"resetsAt":1700002000}
                }}}}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 31)
            try expectEqual(report.weekly?.windowDurationMinutes, 10_080)
            try expectEqual(report.fiveHour, nil)
        },
        TestCase(name: "malformed optional five-hour window does not invalidate weekly usage") {
            let report = try parse(
                """
                {"result":{"rateLimitsByLimitId":{"codex":{
                  "primary":{"usedPercent":101,"windowDurationMins":300,"resetsAt":1700001000},
                  "secondary":{"usedPercent":31,"windowDurationMins":10080,"resetsAt":1700002000}
                }}}}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 31)
            try expectEqual(report.fiveHour, nil)
        },
        TestCase(name: "stale optional five-hour window does not invalidate weekly usage") {
            let report = try parse(
                """
                {"result":{"rateLimitsByLimitId":{"codex":{
                  "primary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":1699999699},
                  "secondary":{"usedPercent":31,"windowDurationMins":10080,"resetsAt":1700002000}
                }}}}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 31)
            try expectEqual(report.fiveHour, nil)
        },
        TestCase(name: "unfamiliar fields are ignored") {
            let report = try parse(
                """
                {"jsonrpc":"2.0","result":{"newField":true,"rateLimits":{"primary":{
                  "usedPercent":7,"windowDurationMins":10080,"resetsAt":1700000300,"future":"value"
                }}}}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 7)
        },
        TestCase(name: "bucket metadata identifies Codex after an identifier rename") {
            let report = try parse(
                """
                {"result":{
                  "rateLimits":{"primary":{"usedPercent":88,"windowDurationMins":10080,"resetsAt":1700001000}},
                  "rateLimitsByLimitId":{"meter-42":{
                    "limitId":"codex","limitName":"Codex coding usage",
                    "primary":{"usedPercent":22,"windowDurationMins":10080,"resetsAt":1700002000}
                  }}
                }}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 22)
        },
        TestCase(name: "a single unfamiliar bucket is an unambiguous compatibility fallback") {
            let report = try parse(
                """
                {"result":{"rateLimitsByLimitId":{"next-generation-meter":{"primary":{
                  "usedPercent":17,"windowDurationMins":10080,"resetsAt":1700002000
                }}}}}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 17)
        },
        TestCase(name: "conflicting unfamiliar buckets fail closed") {
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    """
                    {"result":{"rateLimitsByLimitId":{
                      "meter-a":{"primary":{"usedPercent":17,"windowDurationMins":10080,"resetsAt":1700002000}},
                      "meter-b":{"primary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1700003000}}
                    }}}
                    """
                )
            }
        },
        TestCase(name: "conflicting same-duration windows in one bucket fail closed") {
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    """
                    {"result":{"rateLimitsByLimitId":{"codex":{
                      "primary":{"usedPercent":17,"windowDurationMins":10080,"resetsAt":1700002000},
                      "secondary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1700003000}
                    }}}}
                    """
                )
            }
        },
        TestCase(name: "authoritative conflicts never fall back to legacy data") {
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    """
                    {"result":{
                      "rateLimits":{"primary":{"usedPercent":9,"windowDurationMins":10080,"resetsAt":1700001000}},
                      "rateLimitsByLimitId":{"codex":{
                        "primary":{"usedPercent":17,"windowDurationMins":10080,"resetsAt":1700002000},
                        "secondary":{"usedPercent":42,"windowDurationMins":10080,"resetsAt":1700003000}
                      }}
                    }}
                    """
                )
            }
        },
        TestCase(name: "renamed fields and future window slots remain discoverable") {
            let report = try parse(
                """
                {"result":{"rate_limits_by_limit_id":{"codex-next":{
                  "burst_window":{
                    "used_percentage":37,
                    "window_duration_minutes":300,
                    "reset_at":1700001000
                  },
                  "long_window":{
                    "used_percent":13,
                    "window_duration_mins":10080,
                    "resets_at":1700002000
                  }
                }}}}
                """
            )
            try expectEqual(report.fiveHour?.usedPercent, 37)
            try expectEqual(report.weekly?.usedPercent, 13)
        },
        TestCase(name: "a flattened future bucket remains discoverable") {
            let report = try parse(
                """
                {"result":{"rateLimitsByLimitId":{"codex":{
                  "usedPercent":29,"windowDurationMins":10080,"resetsAt":1700002000
                }}}}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 29)
        },
        TestCase(name: "a malformed sibling bucket does not hide valid Codex usage") {
            let report = try parse(
                """
                {"result":{"rateLimitsByLimitId":{
                  "codex":{"primary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1700000300}},
                  "future-product":"unfamiliar"
                }}}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 7)
        },
        TestCase(name: "lossless integer strings are accepted and still domain validated") {
            let report = try parse(
                """
                {"result":{"rateLimits":{"primary":{
                  "usedPercent":"20","windowDurationMins":"10080","resetsAt":"1700001000"
                }}}}
                """
            )
            try expectEqual(report.weekly?.usedPercent, 20)

            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    #"{"result":{"rateLimits":{"primary":{"usedPercent":"101","windowDurationMins":"10080","resetsAt":"1700001000"}}}}"#
                )
            }
        },
        TestCase(name: "fractional used percent survives decoding") {
            let report = try parse(
                #"{"result":{"rateLimits":{"primary":{"usedPercent":33.5,"windowDurationMins":10080,"resetsAt":1700001000}}}}"#
            )
            try expectEqual(report.weekly?.usedPercent, 33.5)
        },
        TestCase(name: "fractional percent strings are accepted") {
            let report = try parse(
                #"{"result":{"rateLimits":{"primary":{"usedPercent":"24.5","windowDurationMins":10080,"resetsAt":1700001000}}}}"#
            )
            try expectEqual(report.weekly?.usedPercent, 24.5)
        },
        TestCase(name: "out-of-range fractional percents are rejected") {
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    #"{"result":{"rateLimits":{"primary":{"usedPercent":100.5,"windowDurationMins":10080,"resetsAt":1700001000}}}}"#
                )
            }
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    #"{"result":{"rateLimits":{"primary":{"usedPercent":-0.5,"windowDurationMins":10080,"resetsAt":1700001000}}}}"#
                )
            }
        },
        TestCase(name: "server error is surfaced") {
            try expectThrows(CodexResponseParsingError.server("Sign in required")) {
                _ = try parse(#"{"error":{"code":-32000,"message":"Sign in required"}}"#)
            }
        },
        TestCase(name: "invalid JSON is rejected") {
            try expectThrows(CodexResponseParsingError.invalidJSON) {
                _ = try parse("not json")
            }
        },
        TestCase(name: "missing result is rejected") {
            try expectThrows(CodexResponseParsingError.missingResult) {
                _ = try parse(#"{"id":2}"#)
            }
        },
        TestCase(name: "incomplete window is rejected") {
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(#"{"result":{"rateLimits":{"primary":{"usedPercent":20}}}}"#)
            }
        },
        TestCase(name: "five-hour-only response remains usable") {
            let report = try parse(
                #"{"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1700001000}}}}"#
            )
            try expectEqual(report.weekly, nil)
            try expectEqual(report.fiveHour?.usedPercent, 20)
        },
        TestCase(name: "non-positive window duration is rejected") {
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    #"{"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":0,"resetsAt":1700000000}}}}"#
                )
            }
        },
        TestCase(name: "percentage below zero is rejected") {
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    #"{"result":{"rateLimits":{"primary":{"usedPercent":-1,"windowDurationMins":10080,"resetsAt":1700000000}}}}"#
                )
            }
        },
        TestCase(name: "percentage above one hundred is rejected") {
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    #"{"result":{"rateLimits":{"primary":{"usedPercent":101,"windowDurationMins":10080,"resetsAt":1700000000}}}}"#
                )
            }
        },
        TestCase(name: "stale reset timestamp is rejected") {
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    #"{"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1699999699}}}}"#
                )
            }
        },
        TestCase(name: "reset beyond the reported window is rejected") {
            try expectThrows(CodexResponseParsingError.missingUsableWindow) {
                _ = try parse(
                    #"{"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1700605101}}}}"#
                )
            }
        },
    ]
}
