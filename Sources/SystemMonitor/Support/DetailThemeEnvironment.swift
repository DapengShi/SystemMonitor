// Copyright 2024 SystemMonitor Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import SwiftUI

private struct DetailThemeKey: EnvironmentKey {
    @MainActor
    static var defaultValue: DetailThemeController = DetailThemeController(
        initialMode: .system,
        systemColorScheme: nil,
        storage: UserDefaults(),
        persistsSelection: false
    )
}

extension EnvironmentValues {
    var detailTheme: DetailThemeController {
        get { self[DetailThemeKey.self] }
        set { self[DetailThemeKey.self] = newValue }
    }
}

extension View {
    func detailTheme(_ controller: DetailThemeController) -> some View {
        environment(\.detailTheme, controller)
    }
}
