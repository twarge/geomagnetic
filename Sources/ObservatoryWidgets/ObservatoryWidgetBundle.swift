// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0

import WidgetKit
import SwiftUI

@main
struct ObservatoryWidgetBundle: WidgetBundle {
    var body: some Widget {
        ObservatoryFieldWidget()
        ObservatoryChartWidget()
        ObservatoryComponentsWidget()
    }
}
