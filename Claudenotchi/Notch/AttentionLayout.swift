import AppKit
import ClaudenotchiCore

/// Decides how tall the attention panel must be for the request text it shows.
enum AttentionLayout {
    /// Width the request text gets: the panel minus its side padding (16 each), the mascot (32) and the
    /// gap after it (12), with a little slack so a borderline line is counted as wrapping.
    static let textWidth = NotchGeometry.attentionWidth - 32 - 32 - 12 - 8
    static let font = NSFont.systemFont(ofSize: 12)

    /// 1 or 2: how many lines `text` needs. The view allows two lines at most and truncates beyond that.
    static func lineCount(for text: String) -> Int {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let oneLine = font.ascender - font.descender + font.leading
        return bounds.height > oneLine * 1.5 ? 2 : 1
    }
}
