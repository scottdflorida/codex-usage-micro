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
            try expectEqual(report.snapshot.usedPercent, 32)
            try expectEqual(report.snapshot.windowDurationMinutes, 10_080)
            try expectEqual(report.snapshot.resetsAt, Date(timeIntervalSince1970: 1_700_000_000))
        },
        TestCase(name: "legacy bucket is supported") {
            let report = try parse(
                #"{"result":{"rateLimits":{"primary":{"usedPercent":41,"windowDurationMins":10080,"resetsAt":1700000100}}}}"#
            )
            try expectEqual(report.snapshot.usedPercent, 41)
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
            try expectEqual(report.snapshot.usedPercent, 28)
            try expectEqual(report.snapshot.windowDurationMinutes, 10_080)
            try expectEqual(report.snapshot.resetsAt, Date(timeIntervalSince1970: 1_700_600_000))
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
            try expectEqual(report.snapshot.usedPercent, 19)
            try expectEqual(report.snapshot.windowDurationMinutes, 10_080)
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
            try expectEqual(report.snapshot.usedPercent, 12)
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
            try expectEqual(report.snapshot.usedPercent, 22)
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
            try expectEqual(report.snapshot.usedPercent, 31)
            try expectEqual(report.snapshot.windowDurationMinutes, 10_080)
        },
        TestCase(name: "unfamiliar fields are ignored") {
            let report = try parse(
                """
                {"jsonrpc":"2.0","result":{"newField":true,"rateLimits":{"primary":{
                  "usedPercent":7,"windowDurationMins":10080,"resetsAt":1700000300,"future":"value"
                }}}}
                """
            )
            try expectEqual(report.snapshot.usedPercent, 7)
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
