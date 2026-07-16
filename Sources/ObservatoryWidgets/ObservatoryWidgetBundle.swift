// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import WidgetKit
import SwiftUI

@main
struct ObservatoryWidgetBundle: WidgetBundle {
    var body: some Widget {
        ObservatoryChartWidget()
        ObservatoryComponentsWidget()
        #if os(iOS)
        ObservatoryFieldWidget()
        #endif
    }
}
