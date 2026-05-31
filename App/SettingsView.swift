import SwiftUI

// Intentionally empty.
//
// `SettingsView` is provided by `App/SettingsView.swift` (the canonical version
// that routes CSV export through `ExportCSVView` and presents `Paywall`). The
// duplicate `SettingsView` (plus its private `SettingsShareSheet`/`ShareItem`)
// that lived here caused an invalid redeclaration, so it was removed.
