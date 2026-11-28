import Foundation
@testable import GhosttyTerminal
import Testing

/// `readText(scope:)` read off a live surface across viewport, screen, and
/// active scopes without touching selection or program input.
@MainActor
struct TerminalReadTextTests {
    @Test
    func `reads viewport, screen, and active text across scrollback`() async throws {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let surface = try #require(harness.surface)

        let lines = (0 ..< 150).map { String(format: "row%03d", $0) }
        harness.receive("\u{1B}[2J\u{1B}[H" + lines.joined(separator: "\r\n"))

        let screen = try #require(surface.readText(scope: .screen))
        #expect(screen.contains("row000"))
        #expect(screen.contains("row149"))

        let active = try #require(surface.readText(scope: .active))
        #expect(active.contains("row149"))
        #expect(!active.contains("row000"))

        let viewportAtBottom = try #require(surface.readText(scope: .viewport))
        #expect(viewportAtBottom.contains("row149"))

        #expect(surface.scrollToRow(0))
        let viewportAtTop = try #require(surface.readText(scope: .viewport))
        #expect(viewportAtTop.contains("row000"))
        #expect(!viewportAtTop.contains("row149"))
    }

    @Test
    func `dead surface returns nil`() async throws {
        let harness = await GhosttySurfaceHarness.make()
        defer { harness.tearDown() }
        let surface = try #require(harness.surface)

        harness.coordinator.freeSurface()
        #expect(surface.readText(scope: .viewport) == nil)
        #expect(surface.readText(scope: .screen) == nil)
        #expect(surface.readText(scope: .active) == nil)
    }
}
