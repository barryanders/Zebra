import XCTest
@testable import TechnicolorZebraCore

final class TechnicolorZebraTests: XCTestCase {
    func info(transfer: String = "smpte2084", width: Int = 3840, extra: String = "", rate: String = "20000000") throws -> MediaInfo {
        let json = """
        {"streams":[{"codec_type":"video","width":\(width),"height":2160,"color_transfer":"\(transfer)","color_primaries":"bt2020","color_space":"bt2020nc","bit_rate":"\(rate)"\(extra)}],"format":{"duration":"60"}}
        """
        return try JSONDecoder().decode(MediaInfo.self, from: Data(json.utf8))
    }
    func testAcceptsPQAndHLG() throws {
        try info().validateInput()
        try info(transfer: "arib-std-b67").validateInput()
    }
    func testRejectsSDRUnknownAndDolbyVision() throws {
        XCTAssertThrowsError(try info(transfer: "bt709").validateInput())
        XCTAssertThrowsError(try info(transfer: "unknown").validateInput())
        XCTAssertThrowsError(try info(extra: ",\"side_data_list\":[{\"side_data_type\":\"DOVI configuration record\",\"dv_profile\":5}]").validateInput())
    }
    func testRejectsOddDimensionsAndInvalidDuration() throws {
        XCTAssertThrowsError(try info(width: 3839).validateInput())
        let invalid = try JSONDecoder().decode(MediaInfo.self, from: Data("{\"streams\":[],\"format\":{\"duration\":\"nan\"}}".utf8))
        XCTAssertThrowsError(try invalid.validateInput())
    }
    func testBitrateBounds() throws {
        XCTAssertEqual(try info().targetBitrate, 12_000_000)
        XCTAssertEqual(try info(rate: "1").targetBitrate, 6_000_000)
        XCTAssertEqual(try info(rate: "inf").targetBitrate, 7_500_000)
    }
    func testNamesNeverOverwrite() {
        let input = URL(fileURLWithPath: "/media/Example.mkv")
        let result = ConversionPlan.outputURL(for: input) { !$0.hasSuffix(" SDR 3.mkv") }
        XCTAssertEqual(result.lastPathComponent, "Example SDR 3.mkv")
    }
    func testArgumentsPreserveTracksAndAvoidShell() throws {
        let source = URL(fileURLWithPath: "/media/$(touch bad); ' video.mkv")
        let args = ConversionPlan.arguments(input: source, output: URL(fileURLWithPath: "/tmp/out.mkv"), info: try info())
        XCTAssertTrue(args.contains(source.path))
        XCTAssertTrue(args.contains("-n"))
        XCTAssertTrue(args.contains("-protocol_whitelist"))
        XCTAssertTrue(args.contains("file,pipe"))
        XCTAssertFalse(args.contains("-y"))
        XCTAssertTrue(args.contains("0:a?"))
        XCTAssertTrue(args.contains("0:s?"))
        XCTAssertTrue(args.contains("0:t?"))
        XCTAssertFalse(ConversionPlan.filter.contains("scale=w"))
    }
    func testStickyCancellation() {
        let runner = ProcessRunner()
        runner.cancel()
        XCTAssertThrowsError(try runner.run(URL(fileURLWithPath: "/usr/bin/true"), []))
    }
    func testRunningProcessCancellation() throws {
        let runner = ProcessRunner()
        let done = expectation(description: "cancelled")
        DispatchQueue.global().async {
            do {
                _ = try runner.run(URL(fileURLWithPath: "/bin/sleep"), ["30"])
                XCTFail("Expected cancellation")
            } catch { }
            done.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.15)
        runner.cancel()
        wait(for: [done], timeout: 3)
    }
    func testGeneratedHDRConversion() throws {
        guard ProcessInfo.processInfo.environment["DAYLIGHT_INTEGRATION"] == "1" else {
            throw XCTSkip("Set DAYLIGHT_INTEGRATION=1 to run real FFmpeg conversions.")
        }
        let tools = try VideoTools.discover()
        let runner = ProcessRunner()
        try tools.validate(using: runner)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("daylight-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let subs = folder.appendingPathComponent("captions.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nTechnicolorZebra test\n".write(to: subs, atomically: true, encoding: .utf8)
        let metadata = folder.appendingPathComponent("chapters.txt")
        try ";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=900\ntitle=Example\n".write(to: metadata, atomically: true, encoding: .utf8)
        let attachment = folder.appendingPathComponent("note.txt")
        try "Synthetic attachment".write(to: attachment, atomically: true, encoding: .utf8)
        let converter = Converter(tools: tools)
        for transfer in ["smpte2084", "arib-std-b67"] {
            let source = folder.appendingPathComponent("\(transfer) ' sample.mkv")
            _ = try runner.run(tools.ffmpeg, ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24:duration=1", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-i", subs.path, "-f", "ffmetadata", "-i", metadata.path, "-map_chapters", "3", "-attach", attachment.path, "-metadata:s:t", "mimetype=text/plain", "-map", "0:v", "-map", "1:a", "-map", "2:s", "-vf", "setparams=color_primaries=bt2020:color_trc=\(transfer):colorspace=bt2020nc", "-c:v", "libx265", "-x265-params", "colorprim=9:transfer=\(transfer == "smpte2084" ? 16 : 18):colormatrix=9", "-preset", "ultrafast", "-pix_fmt", "yuv420p10le", "-color_primaries", "bt2020", "-color_trc", transfer, "-colorspace", "bt2020nc", "-c:a", "aac", "-c:s", "srt", source.path])
            let original = try Data(contentsOf: source)
            let output = try converter.convert(source) { _ in }
            let result = try converter.probe(output)
            XCTAssertEqual(result.video?.color_transfer, "bt709")
            XCTAssertEqual(result.count("audio"), 1)
            XCTAssertEqual(result.count("subtitle"), 1)
            XCTAssertEqual(result.count("attachment"), 1)
            XCTAssertEqual(result.chapters?.count, 1)
            XCTAssertEqual(result.video?.width, 320)
            XCTAssertEqual(try Data(contentsOf: source), original)
            let second = try converter.convert(source) { _ in }
            XCTAssertNotEqual(second, output)
            XCTAssertThrowsError(try converter.convert(output) { _ in })
            let beforeCancel = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
            let cancelled = Converter(tools: tools)
            XCTAssertThrowsError(try cancelled.convert(source) { progress in
                if progress.stage == "Converting…" { cancelled.runner.cancel() }
            })
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), beforeCancel)
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains(where: { $0.hasPrefix(".daylight-") }))
    }
}
