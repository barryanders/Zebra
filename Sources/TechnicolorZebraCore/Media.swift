import Foundation

public enum TechnicolorZebraError: LocalizedError {
    case message(String), cancelled
    public var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .cancelled: return "Cancelled. Your original is unchanged."
        }
    }
}

public struct MediaInfo: Decodable {
    public struct Stream: Decodable {
        public let codec_type: String?
        public let width: Int?
        public let height: Int?
        public let color_transfer: String?
        public let color_primaries: String?
        public let color_space: String?
        public let bit_rate: String?
        public let tags: [String: String]?
        public let side_data_list: [SideData]?
    }
    public struct SideData: Decodable {
        public let side_data_type: String?
        public let dv_profile: Int?
    }
    public struct Format: Decodable {
        public let duration: String?
        public let bit_rate: String?
    }
    public struct Chapter: Decodable {
        public let start_time: String?
        public let end_time: String?
    }
    public let chapters: [Chapter]?
    public let streams: [Stream]
    public let format: Format
    public var video: Stream? { streams.first { $0.codec_type == "video" } }
    public var duration: Double { Double(format.duration ?? "") ?? 0 }
    public func count(_ type: String) -> Int { streams.filter { $0.codec_type == type }.count }

    public func validateInput() throws {
        guard let video else { throw TechnicolorZebraError.message("No video track found.") }
        guard count("video") == 1 else {
            throw TechnicolorZebraError.message("Multiple video tracks are not supported yet. Nothing was changed.")
        }
        guard duration.isFinite, duration > 0 else { throw TechnicolorZebraError.message("Could not determine video duration.") }
        // Dolby Vision requires profile-aware reshaping; never guess from transfer tags.
        if video.side_data_list?.contains(where: { ($0.side_data_type ?? "").lowercased().contains("dovi") || $0.dv_profile != nil }) == true {
            throw TechnicolorZebraError.message("Dolby Vision is not supported in this version. Use an HDR10 or HLG source.")
        }
        guard ["smpte2084", "arib-std-b67"].contains(video.color_transfer ?? "") else {
            throw TechnicolorZebraError.message("This video is SDR or has unrecognized HDR metadata. No conversion needed or attempted.")
        }
        guard video.color_primaries == "bt2020", video.color_space == "bt2020nc" else {
            throw TechnicolorZebraError.message("This HDR color format is not supported yet. Nothing was changed.")
        }
        guard let width = video.width, let height = video.height, width > 0, height > 0,
              width % 2 == 0, height % 2 == 0 else {
            throw TechnicolorZebraError.message("Unsupported video dimensions.")
        }
    }

    public var targetBitrate: Int {
        let highResolution = (video?.width ?? 0) >= 2500 || (video?.height ?? 0) > 1200
        let streamRate = Double(video?.bit_rate ?? "")
        let taggedRate = Double(video?.tags?["BPS"] ?? "")
        let containerRate = Double(format.bit_rate ?? "")
        let raw: Double = streamRate ?? taggedRate ?? containerRate ?? 6_000_000
        let rate = raw.isFinite && raw > 0 ? raw : 6_000_000
        let floor = highResolution ? 6_000_000.0 : 1_500_000.0
        let ceiling = highResolution ? 12_000_000.0 : 5_000_000.0
        return Int(min(ceiling, max(floor, rate * (highResolution ? 1.25 : 1.5))))
    }
}

public enum ConversionPlan {
    public static let filter = "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=p010le,sidedata=delete:type=MASTERING_DISPLAY_METADATA,sidedata=delete:type=CONTENT_LIGHT_LEVEL,sidedata=delete:type=DYNAMIC_HDR_PLUS"

    public static func arguments(input: URL, output: URL, info: MediaInfo) -> [String] {
        let rate = info.targetBitrate
        return ["-nostdin", "-hide_banner", "-v", "error", "-n", "-protocol_whitelist", "file,pipe", "-i", input.path,
                "-map", "0:v:0", "-map", "0:a?", "-map", "0:s?", "-map", "0:t?",
                "-map_metadata", "0", "-map_chapters", "0", "-vf", filter,
                "-c:v", "hevc_videotoolbox", "-profile:v", "main10", "-b:v", String(rate),
                "-maxrate", String(rate * 3 / 2), "-bufsize", String(rate * 2),
                "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", "-color_range", "tv",
                "-c:a", "copy", "-c:s", "copy", "-c:t", "copy", "-max_muxing_queue_size", "8192",
                "-progress", "pipe:1", "-nostats", output.path]
    }

    public static func outputURL(for source: URL, exists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let folder = source.deletingLastPathComponent()
        var index = 1
        var candidate = folder.appendingPathComponent(base + " SDR.mkv")
        while exists(candidate.path) {
            index += 1
            candidate = folder.appendingPathComponent(base + " SDR \(index).mkv")
        }
        return candidate
    }
}
