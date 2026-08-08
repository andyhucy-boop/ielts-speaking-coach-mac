import XCTest

@testable import IELTSCoachUI

final class AppMetadataTests: XCTestCase {
    private func fullDictionary() -> [String: Any] {
        [
            "CFBundleDisplayName": "IELTS Speaking Coach",
            "CFBundleIdentifier": "com.ielts.speakingcoach",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "42",
            "IELTSBuildCommit": "a1b2c3d",
            "IELTSBuildDate": "2026-08-06T09:00:00Z",
            "IELTSSigningIdentity": "IELTS Coach Dev",
            "IELTSSignatureChannel": "self-signed"
        ]
    }

    func testReadsEveryFieldFromACompleteDictionary() {
        let metadata = AppMetadata.from(infoDictionary: fullDictionary())
        XCTAssertEqual(metadata.displayName, "IELTS Speaking Coach")
        XCTAssertEqual(metadata.bundleIdentifier, "com.ielts.speakingcoach")
        XCTAssertEqual(metadata.shortVersion, "1.0.0")
        XCTAssertEqual(metadata.buildNumber, "42")
        XCTAssertEqual(metadata.buildCommit, "a1b2c3d")
        XCTAssertEqual(metadata.buildDate, "2026-08-06T09:00:00Z")
        XCTAssertEqual(metadata.signingIdentity, "IELTS Coach Dev")
        XCTAssertEqual(metadata.channel, .selfSigned)
    }

    func testMissingDictionaryProducesReadableChineseInsteadOfBlanks() {
        // swift run 直接跑时没有 App bundle，infoDictionary 是 nil。
        // 关于页在这种情况下不能出现空白行、也不能露出 "nil" / "Optional"。
        let metadata = AppMetadata.from(infoDictionary: nil)
        for value in [metadata.displayName, metadata.bundleIdentifier, metadata.shortVersion,
                      metadata.buildNumber, metadata.buildCommit, metadata.buildDate,
                      metadata.signingIdentity] {
            XCTAssertFalse(value.isEmpty, "缺字段时不能返回空串")
            XCTAssertFalse(value.contains("nil"), "不能把 nil 直接显示给用户：\(value)")
            XCTAssertFalse(value.contains("Optional"), "不能把 Optional 直接显示给用户：\(value)")
        }
        XCTAssertEqual(metadata.channel, .unknown)
    }

    func testOnlyTheAbsentKeysFallBack() {
        var dictionary = fullDictionary()
        dictionary.removeValue(forKey: "IELTSBuildCommit")
        let metadata = AppMetadata.from(infoDictionary: dictionary)
        XCTAssertEqual(metadata.buildCommit, AppMetadata.unknownValue)
        XCTAssertEqual(metadata.shortVersion, "1.0.0", "别的字段不该被连坐")
    }

    func testEmptyStringCountsAsMissing() {
        // plist 里把值写成空串，跟没写是一回事：界面上都是空白一行。
        var dictionary = fullDictionary()
        dictionary["IELTSSigningIdentity"] = "   "
        let metadata = AppMetadata.from(infoDictionary: dictionary)
        XCTAssertEqual(metadata.signingIdentity, AppMetadata.unknownValue)
    }

    func testNonStringValuesAreStillDisplayable() {
        // plist 里 CFBundleVersion 被写成 <integer> 是常见事故，不能因此变成「未知」。
        var dictionary = fullDictionary()
        dictionary["CFBundleVersion"] = 99
        let metadata = AppMetadata.from(infoDictionary: dictionary)
        XCTAssertEqual(metadata.buildNumber, "99")
    }

    func testVersionLineCombinesVersionAndBuild() {
        let metadata = AppMetadata.from(infoDictionary: fullDictionary())
        XCTAssertEqual(metadata.versionLine, "1.0.0（构建 42）")
    }

    func testUnknownChannelWhenValueIsGarbage() {
        var dictionary = fullDictionary()
        dictionary["IELTSSignatureChannel"] = "随便写的"
        XCTAssertEqual(AppMetadata.from(infoDictionary: dictionary).channel, .unknown)
    }

    func testEverySignatureChannelExplainsItselfAndGivesANextStep() {
        // 三种通道对用户的含义完全不同（能不能直接双击打开）。
        // 少写一种，用户在别人的电脑上被 Gatekeeper 拦下时就没有任何线索。
        for channel in SignatureChannel.allCases {
            XCTAssertFalse(channel.title.isEmpty, "\(channel) 没有标题")
            XCTAssertFalse(channel.explanation.isEmpty, "\(channel) 没说发生了什么")
            XCTAssertFalse(channel.nextStep.isEmpty, "\(channel) 没说下一步做什么")
        }
    }

    func testSelfSignedTellsTheRecipientHowToGetPastGatekeeper() {
        // 实测：自签名未公证的包 spctl 判定为 rejected。
        // 对方双击打不开时必须能从这句话里知道怎么办。
        let nextStep = SignatureChannel.selfSigned.nextStep
        XCTAssertTrue(nextStep.contains("系统设置"), "没告诉用户去哪儿：\(nextStep)")
        XCTAssertTrue(nextStep.contains("仍要打开"), "没告诉用户点什么：\(nextStep)")

        // 「仍要打开」是系统设置自己的按钮，不是本 App 的控件。
        // 这句话一旦写成「点「仍要打开」」，`RenderReachabilitySweepTests` 的
        // `testEveryButtonNamedInUICopyActuallyExists` 会把它报成幽灵控件
        // （本任务第一版就是这么红的），而它给的两条出路都不成立：
        // 改指自家按钮会把用户引到一颗过不了 Gatekeeper 的按钮上，
        // 「把那颗控件做出来」更不可能——它在 macOS 里。
        // 所以这里钉住写法：这句必须用「打开 / 按下」，把「点「…」」留给自家控件。
        XCTAssertEqual(SourceGuard.clickTargets(in: nextStep), [],
                       "这句话用「点「…」」指了一个不属于本 App 的控件：\(nextStep)")
    }
}
