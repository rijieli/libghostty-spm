//
//  AppTerminalView+ReadText.swift
//  libghostty-spm
//

#if !canImport(UIKit) && canImport(AppKit)
    public extension AppTerminalView {
        /// Reads plain text from the requested terminal region without focusing
        /// the view, touching the clipboard, or altering selection. See
        /// ``TerminalSurface/readText(scope:)``.
        func readText(scope: TerminalTextScope = .viewport) -> String? {
            surface?.readText(scope: scope)
        }
    }
#endif
