//
//  TerminalSurface+ReadText.swift
//  libghostty-spm
//

import Foundation
import GhosttyKit

/// Region of the terminal buffer to read via ``TerminalSurface/readText(scope:)``.
public enum TerminalTextScope: Sendable, Hashable {
    /// Currently visible rows in the viewport.
    case viewport
    /// Entire buffer including scrollback history.
    case screen
    /// Active screen area (without scrollback).
    case active
}

public extension TerminalSurface {
    /// Reads plain text from the requested region without focusing the view,
    /// touching the clipboard, or altering selection. Returns nil when the
    /// surface is gone or Ghostty rejects the read.
    func readText(scope: TerminalTextScope = .viewport) -> String? {
        guard let surface = rawValue else { return nil }
        let tag: ghostty_point_tag_e = switch scope {
        case .viewport: GHOSTTY_POINT_VIEWPORT
        case .screen: GHOSTTY_POINT_SCREEN
        case .active: GHOSTTY_POINT_ACTIVE
        }
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: tag,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0,
            ),
            bottom_right: ghostty_point_s(
                tag: tag,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0,
                y: 0,
            ),
            rectangle: false,
        )
        var result = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &result) else { return nil }
        defer { ghostty_surface_free_text(surface, &result) }
        return result.text.map {
            String(decoding: UnsafeRawBufferPointer(start: $0, count: Int(result.text_len)), as: UTF8.self)
        } ?? ""
    }
}
