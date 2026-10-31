//
//  TerminalSurfaceViewDelegate.swift
//  libghostty-spm
//
//  Created by Lakr233 on 2026/3/16.
//

import CoreGraphics
import Foundation
import GhosttyKit

@MainActor
public protocol TerminalSurfaceViewDelegate: AnyObject {}

@MainActor
public protocol TerminalSurfaceTitleDelegate: TerminalSurfaceViewDelegate {
    func terminalDidChangeTitle(_ title: String)
}

@MainActor
public protocol TerminalSurfaceGridResizeDelegate: TerminalSurfaceViewDelegate {
    func terminalDidResize(_ size: TerminalGridMetrics)
}

@MainActor
public protocol TerminalSurfaceResizeDelegate: TerminalSurfaceViewDelegate {
    func terminalDidResize(columns: Int, rows: Int)
}

@MainActor
public protocol TerminalSurfaceFocusDelegate: TerminalSurfaceViewDelegate {
    func terminalDidChangeFocus(_ focused: Bool)
}

@MainActor
public protocol TerminalSurfaceBellDelegate: TerminalSurfaceViewDelegate {
    func terminalDidRingBell()
}

/// Scrollback search, driven by the `start_search`, `search:<needle>`, `navigate_search:next` /
/// `:previous` and `end_search` binding actions. The core reports back here: a search to show
/// (with the needle it starts from, such as the selection), its end, the number of matches and
/// which one is selected. A count or index the core doesn't know yet arrives as nil.
@MainActor
public protocol TerminalSurfaceSearchDelegate: TerminalSurfaceViewDelegate {
    func terminalDidStartSearch(needle: String?)
    func terminalDidEndSearch()
    func terminalDidUpdateSearchTotal(_ total: Int?)
    func terminalDidUpdateSearchSelected(_ selected: Int?)
}

@MainActor
public protocol TerminalSurfaceCloseDelegate: TerminalSurfaceViewDelegate {
    func terminalDidClose(processAlive: Bool)
}

/// The operation that caused Ghostty to request a clipboard decision.
public enum TerminalClipboardRequestKind: Sendable {
    case paste
    case osc52Read
    case osc52Write

    init?(_ rawValue: ghostty_clipboard_request_e) {
        switch rawValue {
        case GHOSTTY_CLIPBOARD_REQUEST_PASTE:
            self = .paste
        case GHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ:
            self = .osc52Read
        case GHOSTTY_CLIPBOARD_REQUEST_OSC_52_WRITE:
            self = .osc52Write
        default:
            return nil
        }
    }
}

/// A one-shot host decision for an unsafe or otherwise protected clipboard
/// request. Hosts must call ``respond(allow:)`` exactly once. Dropping an
/// unanswered request cancels it.
@MainActor
public final class TerminalClipboardConfirmationRequest {
    public let contents: String
    public let kind: TerminalClipboardRequestKind

    private var completion: ((Bool) -> Void)?

    init(
        contents: String,
        kind: TerminalClipboardRequestKind,
        completion: @escaping (Bool) -> Void,
    ) {
        self.contents = contents
        self.kind = kind
        self.completion = completion
    }

    public func respond(allow: Bool) {
        guard let completion else { return }
        self.completion = nil
        completion(allow)
    }

    deinit {
        MainActor.assumeIsolated {
            completion?(false)
        }
    }
}

/// Lets an embedding host own confirmation UI for unsafe paste and protected
/// OSC 52 operations. If the delegate does not implement this protocol, the
/// request is denied.
@MainActor
public protocol TerminalSurfaceClipboardConfirmationDelegate: TerminalSurfaceViewDelegate {
    func terminalDidRequestClipboardConfirmation(
        _ request: TerminalClipboardConfirmationRequest,
    )
}

// MARK: - Extended action delegates

/// State of an OSC 9;4 / DECSET progress report.
public enum TerminalProgressState: Sendable {
    case remove
    case set
    case error
    case indeterminate
    case pause

    init?(_ raw: ghostty_action_progress_report_state_e) {
        switch raw {
        case GHOSTTY_PROGRESS_STATE_REMOVE: self = .remove
        case GHOSTTY_PROGRESS_STATE_SET: self = .set
        case GHOSTTY_PROGRESS_STATE_ERROR: self = .error
        case GHOSTTY_PROGRESS_STATE_INDETERMINATE: self = .indeterminate
        case GHOSTTY_PROGRESS_STATE_PAUSE: self = .pause
        default: return nil
        }
    }
}

/// OSC 9;4 progress report (state + 0-100 percent, nil percent when the
/// emitter didn't provide one — e.g. INDETERMINATE / REMOVE).
@MainActor
public protocol TerminalSurfaceProgressReportDelegate: TerminalSurfaceViewDelegate {
    func terminalDidReportProgress(state: TerminalProgressState, percent: Int?)
}

/// State of an OSC 7501 program status report.
public enum TerminalProgramState: Hashable, Sendable {
    case idle
    case working
    case done
    /// Waiting on the user; the kind says for what, when the program sent one.
    case blocked(TerminalProgramBlockKind?)
    case error
    /// Not a state: the program withdrew its status.
    case clear

    init?(_ raw: ghostty_action_program_status_s) {
        switch raw.state {
        case GHOSTTY_PROGRAM_STATUS_STATE_IDLE: self = .idle
        case GHOSTTY_PROGRAM_STATUS_STATE_WORKING: self = .working
        case GHOSTTY_PROGRAM_STATUS_STATE_DONE: self = .done
        case GHOSTTY_PROGRAM_STATUS_STATE_BLOCKED:
            self = .blocked(TerminalProgramBlockKind(rawValue: raw.kind))
        case GHOSTTY_PROGRAM_STATUS_STATE_ERROR: self = .error
        case GHOSTTY_PROGRAM_STATUS_STATE_CLEAR: self = .clear
        default: return nil
        }
    }
}

/// What a blocked OSC 7501 program needs from the user.
public enum TerminalProgramBlockKind: Hashable, Sendable {
    case permission
    case question
    case auth

    init?(rawValue: Int32) {
        switch UInt32(bitPattern: rawValue) {
        case GHOSTTY_PROGRAM_STATUS_KIND_PERMISSION.rawValue: self = .permission
        case GHOSTTY_PROGRAM_STATUS_KIND_QUESTION.rawValue: self = .question
        case GHOSTTY_PROGRAM_STATUS_KIND_AUTH.rawValue: self = .auth
        default: return nil
        }
    }
}

/// OSC 7501 program status: what the program is doing, with a 0-100
/// percent when it reported one. Each report replaces the previous one.
@MainActor
public protocol TerminalSurfaceProgramStatusDelegate: TerminalSurfaceViewDelegate {
    func terminalDidReportProgramStatus(state: TerminalProgramState, percent: Int?)
}

/// A validated OSC 7501 report. Optional text belongs to this report only;
/// reports replace the previous record rather than inheriting its fields.
public struct TerminalProgramStatusReport: Sendable, Equatable {
    public let state: TerminalProgramState
    public let percent: Int?
    public let id: String?
    public let app: String?
    public let title: String?
    public let message: String?

    init?(_ raw: ghostty_action_program_status_s) {
        guard let state = TerminalProgramState(raw) else { return nil }
        self.state = state
        percent = raw.progress < 0 ? nil : Int(raw.progress)
        let data = String(decoding: UnsafeBufferPointer(start: raw.data, count: Int(raw.data_len)), as: UTF8.self)
        var fields: [String: String] = [:]
        let valueBytes = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.+-,/=")
        for pair in data.split(separator: ":") {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            let key = pair[..<equals].trimmingCharacters(in: .whitespaces)
            let value = pair[pair.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard value.unicodeScalars.allSatisfy(valueBytes.contains) else { continue }
            fields[key] = value
        }
        id = fields["id"].flatMap { $0.isEmpty ? nil : $0 }
        app = fields["app"].flatMap { value in
            let nameBytes = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.+-")
            return !value.isEmpty && value.unicodeScalars.allSatisfy(nameBytes.contains) ? value : nil
        }
        title = fields["title"].flatMap { value in
            guard !value.isEmpty else { return nil }
            let padded = value + String(repeating: "=", count: (4 - value.count % 4) % 4)
            return Data(base64Encoded: padded).flatMap { String(data: $0, encoding: .utf8) }
        }
        message = fields["msg"].flatMap { value in
            guard !value.isEmpty else { return nil }
            let padded = value + String(repeating: "=", count: (4 - value.count % 4) % 4)
            return Data(base64Encoded: padded).flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}

/// Receives the additional optional fields in OSC 7501 reports.
@MainActor
public protocol TerminalSurfaceProgramStatusDetailsDelegate: TerminalSurfaceViewDelegate {
    func terminalDidReportProgramStatus(_ report: TerminalProgramStatusReport)
}

public enum TerminalColorChangeKind: Hashable, Sendable {
    case foreground
    case background
    case cursor
    case palette(Int)

    init(_ raw: ghostty_action_color_kind_e) {
        switch raw {
        case GHOSTTY_ACTION_COLOR_KIND_FOREGROUND: self = .foreground
        case GHOSTTY_ACTION_COLOR_KIND_BACKGROUND: self = .background
        case GHOSTTY_ACTION_COLOR_KIND_CURSOR: self = .cursor
        default: self = .palette(Int(raw.rawValue))
        }
    }
}

public struct TerminalColorChange: Hashable, Sendable {
    public let kind: TerminalColorChangeKind
    public let color: TerminalColor

    public init(kind: TerminalColorChangeKind, color: TerminalColor) {
        self.kind = kind
        self.color = color
    }
}

/// OSC 10/11/12 and OSC 4; a reset (OSC 110/111/112, OSC 104) arrives as a
/// change back to the config's color.
@MainActor
public protocol TerminalSurfaceColorChangeDelegate: TerminalSurfaceViewDelegate {
    func terminalDidChangeColor(_ change: TerminalColorChange)
}

/// Fires when a shell-integration-aware command exits. `exitCode` is nil
/// when not reported; `duration` is the wall clock in nanoseconds.
@MainActor
public protocol TerminalSurfaceCommandFinishedDelegate: TerminalSurfaceViewDelegate {
    func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64)
}

/// OSC 9 (iTerm2) / OSC 777 (rxvt-unicode) desktop notification.
/// Empty title/body surface as empty strings rather than nil.
@MainActor
public protocol TerminalSurfaceDesktopNotificationDelegate: TerminalSurfaceViewDelegate {
    func terminalDidRequestDesktopNotification(title: String, body: String)
}

public enum TerminalOpenURLKind: Sendable {
    case unknown
    case text
    case html

    init(_ raw: ghostty_action_open_url_kind_e) {
        switch raw {
        case GHOSTTY_ACTION_OPEN_URL_KIND_TEXT: self = .text
        case GHOSTTY_ACTION_OPEN_URL_KIND_HTML: self = .html
        default: self = .unknown
        }
    }
}

/// User activated (cmd-clicked) a hyperlink inside the terminal grid.
@MainActor
public protocol TerminalSurfaceOpenURLDelegate: TerminalSurfaceViewDelegate {
    func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind)
}

/// Mouse hovered over a recognized hyperlink. nil = hover ended / link lost.
@MainActor
public protocol TerminalSurfaceHoverLinkDelegate: TerminalSurfaceViewDelegate {
    func terminalDidUpdateHoverLink(_ url: String?)
}

/// Ghostty mouse cursor shape (OSC 22 / application request).
public enum TerminalMouseShape: Sendable, Equatable {
    case `default`
    case pointer
    case text
    case notAllowed
    case other

    init(_ raw: ghostty_action_mouse_shape_e) {
        switch raw {
        case GHOSTTY_MOUSE_SHAPE_DEFAULT:
            self = .default
        case GHOSTTY_MOUSE_SHAPE_POINTER:
            self = .pointer
        case GHOSTTY_MOUSE_SHAPE_TEXT, GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT, GHOSTTY_MOUSE_SHAPE_CELL:
            self = .text
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED, GHOSTTY_MOUSE_SHAPE_NO_DROP:
            self = .notAllowed
        default:
            self = .other
        }
    }
}

@MainActor
public protocol TerminalSurfaceMouseShapeDelegate: TerminalSurfaceViewDelegate {
    func terminalDidChangeMouseShape(_ shape: TerminalMouseShape)
}

/// OSC 7 working-directory update.
@MainActor
public protocol TerminalSurfacePwdDelegate: TerminalSurfaceViewDelegate {
    func terminalDidChangeWorkingDirectory(_ path: String)
}

/// Scrollbar geometry reported by the terminal, in rows: `offset` rows are
/// scrolled off above the viewport, `len` rows are visible, out of `total`
/// rows of content (scrollback + screen).
public struct TerminalScrollbar: Equatable, Sendable {
    public let total: UInt64
    public let offset: UInt64
    public let len: UInt64

    public init(total: UInt64, offset: UInt64, len: UInt64) {
        self.total = total
        self.offset = offset
        self.len = len
    }
}

/// The scrollbar geometry changed (the viewport scrolled or the content grew).
@MainActor
public protocol TerminalSurfaceScrollbarDelegate: TerminalSurfaceViewDelegate {
    func terminalDidUpdateScrollbar(_ scrollbar: TerminalScrollbar)
}

/// The surface's font size changed, in points: a pinch (iOS), Cmd+=, Cmd+-
/// or Cmd+0 on a hardware keyboard, a font-size binding action from the host,
/// a config reload that moved an unzoomed surface, or a new surface starting
/// at a different size than the last one. Fires only when the size actually
/// moved. A host that remembers zoom feeds this into the *next* surface's
/// ``TerminalSurfaceOptions/fontSize``; writing it into this surface's own
/// options rebuilds the surface.
///
/// The C API has no font-size getter, so the wrapper tracks the size itself,
/// rule for rule with Ghostty. Font-size actions sent through the raw
/// ``TerminalSurface`` count too; a keybind that a custom config moves off
/// Cmd+=/-/0 does not.
@MainActor
public protocol TerminalSurfaceFontSizeDelegate: TerminalSurfaceViewDelegate {
    func terminalDidChangeFontSize(_ fontSize: Float)
}

/// Notifies a delegate when the underlying ``TerminalSurface`` is created or
/// torn down. Useful when a consumer needs surface-level APIs (e.g.
/// ``TerminalSurface/paste(text:)``) reachable from outside the platform view.
@MainActor
public protocol TerminalSurfaceLifecycleDelegate: TerminalSurfaceViewDelegate {
    func terminalDidAttachSurface(_ surface: TerminalSurface)
    func terminalDidDetachSurface()
}

// MARK: - Clipboard content

/// One MIME-typed clipboard representation. Binary-safe: `data` may contain
/// non-UTF8 bytes and is never implicitly text, even for a `mime` that looks
/// text-like.
public struct TerminalClipboardContent: Sendable {
    public let mime: String
    public let data: Data

    public init(mime: String, data: Data) {
        self.mime = mime
        self.data = data
    }
}
