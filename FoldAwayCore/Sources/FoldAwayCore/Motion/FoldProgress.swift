import Foundation

/// Maps a lid angle to effect progress 0…1: 0 at `start` and
/// above, 1 at `end` and below, smoothstep in between.
public enum FoldProgress {
    public static func progress(angle: Double, start: Double, end: Double) -> Double {
        guard start > end else { return angle <= end ? 1 : 0 }
        let t = max(0, min(1, (start - angle) / (start - end)))
        return t * t * (3 - 2 * t)
    }
}
