import Foundation

/// Appends to ~/Library/Logs/ClamshellPoC.log and stdout, so results survive the lid closing.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/ClamshellPoC.log")
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()
    static var sink: ((String) -> Void)?

    static func w(_ s: String) {
        let line = "\(fmt.string(from: Date())) \(s)"
        print(line)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close()
        } else {
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        DispatchQueue.main.async { sink?(line) }
    }
}
