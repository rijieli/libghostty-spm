//
//  TerminalProgramStatus.swift
//  libghostty-spm
//

import Foundation
import GhosttyKit

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
