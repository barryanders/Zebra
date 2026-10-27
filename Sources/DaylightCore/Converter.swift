import Foundation

/// One worker per queue run. Cancellation is sticky and applies to probing and validation too.
public final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    public init() {}
    public func cancel() {
        lock.lock()
        cancelled = true
        if let process, process.isRunning { process.terminate() }
        lock.unlock()
    }
    public func checkCancellation() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw DaylightError.cancelled }
    }
    public func run(_ executable: URL, _ arguments: [String], line: ((String) -> Void)? = nil) throws -> Data {
        try checkCancellation()
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        let stdout = Pipe()
        task.standardOutput = stdout
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("daylight-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw DaylightError.message("Could not create a temporary log.")
        }
        defer { try? FileManager.default.removeItem(at: log) }
        let stderr = try FileHandle(forWritingTo: log)
        defer { try? stderr.close() }
        task.standardError = stderr
        // Starting under the lock prevents cancellation between registration and launch.
        lock.lock()
        if cancelled { lock.unlock(); throw DaylightError.cancelled }
        do { try task.run(); process = task; lock.unlock() }
        catch { lock.unlock(); throw error }
        var output = Data()
        var pending = Data()
        while true {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            if let line {
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    line(String(decoding: pending[..<newline], as: UTF8.self))
                    pending.removeSubrange(...newline)
                }
            } else { output.append(chunk) }
        }
        task.waitUntilExit()
        lock.lock(); process = nil; lock.unlock()
        try checkCancellation()
        guard task.terminationStatus == 0 else {
            let details = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw DaylightError.message(details.isEmpty ? "The video tool stopped unexpectedly." : String(details.suffix(1800)))
        }
        return output
    }
}

public struct VideoTools: Sendable {
    public let ffmpeg: URL
    public let ffprobe: URL
    public init(ffmpeg: URL, ffprobe: URL) { self.ffmpeg = ffmpeg; self.ffprobe = ffprobe }
    public static func discover() throws -> VideoTools {
        let prefixes = ["/opt/homebrew/opt/ffmpeg-full/bin", "/usr/local/opt/ffmpeg-full/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        for prefix in prefixes {
            let a = URL(fileURLWithPath: prefix).appendingPathComponent("ffmpeg")
            let b = URL(fileURLWithPath: prefix).appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: a.path), FileManager.default.isExecutableFile(atPath: b.path) {
                return VideoTools(ffmpeg: a, ffprobe: b)
            }
        }
        throw DaylightError.message("Daylight needs FFmpeg. Install Homebrew, then run: brew install ffmpeg-full")
    }
    public func validate(using runner: ProcessRunner) throws {
        let filters = String(decoding: try runner.run(ffmpeg, ["-hide_banner", "-filters"]), as: UTF8.self)
        guard filters.contains("zscale"), filters.contains("tonemap") else {
            throw DaylightError.message("This FFmpeg build lacks HDR tone mapping. Run: brew install ffmpeg-full")
        }
        let encoders = String(decoding: try runner.run(ffmpeg, ["-hide_banner", "-encoders"]), as: UTF8.self)
        guard encoders.contains("hevc_videotoolbox") else { throw DaylightError.message("FFmpeg needs Apple's HEVC VideoToolbox encoder.") }
    }
}

public struct ConversionUpdate: Sendable {
    public let fraction: Double
    public let stage: String
    public init(_ fraction: Double, _ stage: String) { self.fraction = fraction; self.stage = stage }
}

public final class Converter: @unchecked Sendable {
    public let runner: ProcessRunner
    private let tools: VideoTools
    public init(tools: VideoTools, runner: ProcessRunner = ProcessRunner()) { self.tools = tools; self.runner = runner }
    public func probe(_ url: URL) throws -> MediaInfo {
        let data = try runner.run(tools.ffprobe, ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_chapters", "-show_format", "-of", "json", url.path])
        return try JSONDecoder().decode(MediaInfo.self, from: data)
    }
    public func convert(_ input: URL, update: @escaping (ConversionUpdate) -> Void) throws -> URL {
        guard input.isFileURL else { throw DaylightError.message("Only local files are supported.") }
        let fm = FileManager.default
        let attributes = try fm.attributesOfItem(atPath: input.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw DaylightError.message("Drop video files, not folders or aliases.") }
        update(.init(0, "Checking video…"))
        let info = try probe(input)
        try info.validateInput()
        let output = ConversionPlan.outputURL(for: input)
        let partial = input.deletingLastPathComponent().appendingPathComponent(".daylight-\(UUID().uuidString).mkv")
        defer { try? fm.removeItem(at: partial) }
        _ = try runner.run(tools.ffmpeg, ConversionPlan.arguments(input: input, output: partial, info: info)) { line in
            if line.hasPrefix("out_time_us="), let micros = Double(line.dropFirst(12)), micros.isFinite {
                update(.init(min(0.85, max(0, micros / 1_000_000 / info.duration * 0.85)), "Converting…"))
            }
        }
        update(.init(0.86, "Checking SDR copy…"))
        let result = try probe(partial)
        guard abs(result.duration - info.duration) < max(1, info.duration * 0.001),
              result.video?.width == info.video?.width, result.video?.height == info.video?.height,
              result.video?.color_transfer == "bt709", result.video?.color_primaries == "bt709", result.video?.color_space == "bt709",
              result.count("audio") == info.count("audio"), result.count("subtitle") == info.count("subtitle"),
              result.count("attachment") == info.count("attachment"),
              (result.chapters?.count ?? 0) == (info.chapters?.count ?? 0) else {
            throw DaylightError.message("The SDR copy failed verification. Your original is unchanged.")
        }
        let hdrData = result.video?.side_data_list?.contains { data in
            let type = (data.side_data_type ?? "").lowercased()
            return type.contains("mastering") || type.contains("content light") || type.contains("hdr") || type.contains("dovi")
        } ?? false
        guard !hdrData else { throw DaylightError.message("Unexpected HDR metadata remains. Your original is unchanged.") }
        _ = try runner.run(tools.ffmpeg, ["-nostdin", "-v", "error", "-xerror", "-protocol_whitelist", "file,pipe", "-i", partial.path, "-map", "0:v:0", "-map", "0:a?", "-f", "null", "-"])
        try runner.checkCancellation()
        let current = try fm.attributesOfItem(atPath: input.path)
        guard attributes[.size] as? NSNumber == current[.size] as? NSNumber,
              attributes[.modificationDate] as? Date == current[.modificationDate] as? Date else {
            throw DaylightError.message("The source changed during conversion. Please try again.")
        }
        // moveItem refuses an existing destination, including a concurrent writer's file.
        try fm.moveItem(at: partial, to: output)
        update(.init(1, "SDR copy ready"))
        return output
    }
}
