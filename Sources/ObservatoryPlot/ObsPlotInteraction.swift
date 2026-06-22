// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Pan/zoom interaction, ported from HiDeF. macOS uses trackpad scroll + magnify + drag
// selection; iOS uses two-finger pan + pinch + double-tap reset. watchOS gets a static
// plot (the overlay collapses to an empty layer).

import SwiftUI

enum ObsPlotZoomAxis {
    case horizontal
    case vertical
}

enum ObsPlotDragZoomMode {
    case rectangular
    case horizontal
    case vertical

    var updatesHorizontal: Bool { self != .vertical }
    var updatesVertical: Bool { self != .horizontal }
}

struct ObsPlotDragSelection {
    let rect: CGRect
    let mode: ObsPlotDragZoomMode

    init(start: CGPoint, end: CGPoint) {
        rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        mode = Self.mode(for: CGSize(width: end.x - start.x, height: end.y - start.y))
    }

    func previewRect(in plotRect: CGRect) -> CGRect? {
        switch mode {
        case .rectangular:
            let clippedRect = rect.intersection(plotRect)
            guard !clippedRect.isNull, !clippedRect.isEmpty else { return nil }
            guard clippedRect.width >= 4, clippedRect.height >= 4 else { return nil }
            return clippedRect
        case .horizontal:
            let minX = max(rect.minX, plotRect.minX)
            let maxX = min(rect.maxX, plotRect.maxX)
            let width = maxX - minX
            guard width >= 4 else { return nil }
            return CGRect(x: minX, y: plotRect.minY, width: width, height: plotRect.height)
        case .vertical:
            let minY = max(rect.minY, plotRect.minY)
            let maxY = min(rect.maxY, plotRect.maxY)
            let height = maxY - minY
            guard height >= 4 else { return nil }
            return CGRect(x: plotRect.minX, y: minY, width: plotRect.width, height: height)
        }
    }

    func isLargeEnough(minimumDistance: CGFloat) -> Bool {
        switch mode {
        case .rectangular: rect.width >= minimumDistance && rect.height >= minimumDistance
        case .horizontal:  rect.width >= minimumDistance
        case .vertical:    rect.height >= minimumDistance
        }
    }

    private static func mode(for translation: CGSize) -> ObsPlotDragZoomMode {
        let width = abs(translation.width)
        let height = abs(translation.height)
        guard width > 0 || height > 0 else { return .rectangular }

        let axisLockSlope: CGFloat = 0.364
        if height <= width * axisLockSlope { return .horizontal }
        if width <= height * axisLockSlope { return .vertical }
        return .rectangular
    }
}

struct ObsPlotZoom {
    let axis: ObsPlotZoomAxis
    let scale: CGFloat

    static func dominant(horizontalScale: CGFloat, verticalScale: CGFloat,
                         fallbackScale: CGFloat? = nil, verticalPreference: CGFloat = 1) -> ObsPlotZoom? {
        let cleanHorizontal = cleanScale(horizontalScale)
        let cleanVertical = cleanScale(verticalScale)
        let horizontalMagnitude = magnitude(of: cleanHorizontal)
        let verticalMagnitude = magnitude(of: cleanVertical)

        if horizontalMagnitude == 0, verticalMagnitude == 0, let fallbackScale {
            return ObsPlotZoom(axis: .horizontal, scale: cleanScale(fallbackScale))
        }
        if verticalMagnitude > horizontalMagnitude * verticalPreference {
            return ObsPlotZoom(axis: .vertical, scale: cleanVertical)
        }
        return ObsPlotZoom(axis: .horizontal, scale: cleanHorizontal)
    }

    static func single(axis: ObsPlotZoomAxis, scale: CGFloat) -> ObsPlotZoom? {
        let clean = cleanScale(scale)
        guard magnitude(of: clean) > 0 else { return nil }
        return ObsPlotZoom(axis: axis, scale: clean)
    }

    private static func cleanScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return 1 }
        return min(64, max(0.015625, scale))
    }

    private static func magnitude(of scale: CGFloat) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return 0 }
        return CGFloat(abs(log(Double(scale))))
    }
}

struct ObsPlotTouchSpan {
    let width: CGFloat
    let height: CGFloat

    static func span(for points: [CGPoint]) -> ObsPlotTouchSpan? {
        guard points.count >= 2 else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        return ObsPlotTouchSpan(width: maxX - minX, height: maxY - minY)
    }

    func zoom(to next: ObsPlotTouchSpan, minimumSpan: CGFloat,
              fallbackScale: CGFloat? = nil, verticalPreference: CGFloat = 1) -> ObsPlotZoom? {
        let horizontalScale = axisScale(from: width, to: next.width, minimumSpan: minimumSpan)
        let verticalScale = axisScale(from: height, to: next.height, minimumSpan: minimumSpan)
        return ObsPlotZoom.dominant(horizontalScale: horizontalScale, verticalScale: verticalScale,
                                    fallbackScale: fallbackScale, verticalPreference: verticalPreference)
    }

    private func axisScale(from previous: CGFloat, to next: CGFloat, minimumSpan: CGFloat) -> CGFloat {
        guard previous >= minimumSpan, next >= minimumSpan else { return 1 }
        return next / previous
    }
}

/// Platform-bridged interaction surface. Collapses to an empty layer on watchOS.
struct ObsPlotInteractionOverlay: View {
    let onPan: (CGSize) -> Void
    let onZoom: (ObsPlotZoom) -> Void
    let onContinuousZoomBegan: () -> Void
    let onContinuousZoomEnded: () -> Void
    let onReset: () -> Void
    let onZoomSelectionChanged: (ObsPlotDragSelection?) -> Void
    let onZoomSelectionEnded: (ObsPlotDragSelection) -> Void

    var body: some View {
        #if os(macOS)
        ObsMacPlotInteractionView(
            onPan: onPan, onZoom: onZoom,
            onContinuousZoomBegan: onContinuousZoomBegan, onContinuousZoomEnded: onContinuousZoomEnded,
            onReset: onReset, onZoomSelectionChanged: onZoomSelectionChanged,
            onZoomSelectionEnded: onZoomSelectionEnded)
        #elseif os(iOS)
        ObsIOSPlotInteractionView(
            onPan: onPan, onZoom: onZoom,
            onContinuousZoomBegan: onContinuousZoomBegan, onContinuousZoomEnded: onContinuousZoomEnded,
            onReset: onReset)
        #else
        Color.clear
        #endif
    }
}

#if os(macOS)
import AppKit

private struct ObsMacPlotInteractionView: NSViewRepresentable {
    let onPan: (CGSize) -> Void
    let onZoom: (ObsPlotZoom) -> Void
    let onContinuousZoomBegan: () -> Void
    let onContinuousZoomEnded: () -> Void
    let onReset: () -> Void
    let onZoomSelectionChanged: (ObsPlotDragSelection?) -> Void
    let onZoomSelectionEnded: (ObsPlotDragSelection) -> Void

    func makeNSView(context: Context) -> ObsMacPlotInteractionNSView {
        let view = ObsMacPlotInteractionNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: ObsMacPlotInteractionNSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: ObsMacPlotInteractionNSView) {
        view.onPan = onPan
        view.onZoom = onZoom
        view.onContinuousZoomBegan = onContinuousZoomBegan
        view.onContinuousZoomEnded = onContinuousZoomEnded
        view.onReset = onReset
        view.onZoomSelectionChanged = onZoomSelectionChanged
        view.onZoomSelectionEnded = onZoomSelectionEnded
    }
}

private final class ObsMacPlotInteractionNSView: NSView {
    var onPan: ((CGSize) -> Void)?
    var onZoom: ((ObsPlotZoom) -> Void)?
    var onContinuousZoomBegan: (() -> Void)?
    var onContinuousZoomEnded: (() -> Void)?
    var onReset: (() -> Void)?
    var onZoomSelectionChanged: ((ObsPlotDragSelection?) -> Void)?
    var onZoomSelectionEnded: ((ObsPlotDragSelection) -> Void)?
    private var lastMagnificationSpan: ObsPlotTouchSpan?
    private var isMagnifying = false
    private var dragStart: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = true
    }

    required init?(coder: NSCoder) { nil }

    override func scrollWheel(with event: NSEvent) {
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        let translation = CGSize(width: event.scrollingDeltaX * multiplier,
                                 height: event.scrollingDeltaY * multiplier)
        if translation != .zero { onPan?(translation) }
    }

    override func magnify(with event: NSEvent) {
        let fallbackScale = max(0.05, 1 + event.magnification)
        let currentSpan = Self.touchSpan(from: event, in: self)

        if event.phase == .began {
            beginMagnificationIfNeeded()
            lastMagnificationSpan = currentSpan
            return
        }

        beginMagnificationIfNeeded()
        if let currentSpan {
            if let previousSpan = lastMagnificationSpan,
               let zoom = previousSpan.zoom(to: currentSpan, minimumSpan: 0.002, fallbackScale: fallbackScale) {
                onZoom?(zoom)
            }
            lastMagnificationSpan = currentSpan
        } else if let zoom = ObsPlotZoom.dominant(horizontalScale: fallbackScale, verticalScale: 1, fallbackScale: fallbackScale) {
            onZoom?(zoom)
        }

        if event.phase == .ended || event.phase == .cancelled {
            lastMagnificationSpan = nil
            endMagnificationIfNeeded()
        }
    }

    override func smartMagnify(with event: NSEvent) { onReset?() }

    override func mouseDown(with event: NSEvent) {
        dragStart = point(from: event)
        onZoomSelectionChanged?(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        onZoomSelectionChanged?(ObsPlotDragSelection(start: dragStart, end: point(from: event)))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            onZoomSelectionChanged?(nil)
        }
        guard let dragStart else { return }
        let selection = ObsPlotDragSelection(start: dragStart, end: point(from: event))
        guard selection.isLargeEnough(minimumDistance: 6) else { return }
        onZoomSelectionEnded?(selection)
    }

    private static func touchSpan(from event: NSEvent, in view: NSView) -> ObsPlotTouchSpan? {
        let points = event.touches(matching: .touching, in: view).map { touch in
            CGPoint(x: touch.normalizedPosition.x, y: touch.normalizedPosition.y)
        }
        return ObsPlotTouchSpan.span(for: points)
    }

    private func beginMagnificationIfNeeded() {
        guard !isMagnifying else { return }
        isMagnifying = true
        onContinuousZoomBegan?()
    }

    private func endMagnificationIfNeeded() {
        guard isMagnifying else { return }
        isMagnifying = false
        onContinuousZoomEnded?()
    }

    private func point(from event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }
}
#elseif os(iOS)
import UIKit

private struct ObsIOSPlotInteractionView: UIViewRepresentable {
    let onPan: (CGSize) -> Void
    let onZoom: (ObsPlotZoom) -> Void
    let onContinuousZoomBegan: () -> Void
    let onContinuousZoomEnded: () -> Void
    let onReset: () -> Void

    func makeUIView(context: Context) -> ObsIOSPlotInteractionUIView {
        let view = ObsIOSPlotInteractionUIView()
        apply(to: view)
        return view
    }

    func updateUIView(_ uiView: ObsIOSPlotInteractionUIView, context: Context) {
        apply(to: uiView)
    }

    private func apply(to view: ObsIOSPlotInteractionUIView) {
        view.onPan = onPan
        view.onZoom = onZoom
        view.onContinuousZoomBegan = onContinuousZoomBegan
        view.onContinuousZoomEnded = onContinuousZoomEnded
        view.onReset = onReset
    }
}

private final class ObsIOSPlotInteractionUIView: UIView, UIGestureRecognizerDelegate {
    var onPan: ((CGSize) -> Void)?
    var onZoom: ((ObsPlotZoom) -> Void)?
    var onContinuousZoomBegan: (() -> Void)?
    var onContinuousZoomEnded: (() -> Void)?
    var onReset: (() -> Void)?

    private var lastPinchScale: CGFloat = 1
    private var lockedPinchAxis: ObsPlotZoomAxis?
    private var isPinching = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)

        let scrollPan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        scrollPan.allowedScrollTypesMask = .all
        scrollPan.minimumNumberOfTouches = 0
        scrollPan.maximumNumberOfTouches = 0
        scrollPan.delegate = self
        addGestureRecognizer(scrollPan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let reset = UITapGestureRecognizer(target: self, action: #selector(handleReset(_:)))
        reset.numberOfTapsRequired = 2
        reset.numberOfTouchesRequired = 2
        reset.delegate = self
        addGestureRecognizer(reset)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let point = recognizer.translation(in: self)
        let translation = CGSize(width: point.x, height: point.y)
        if translation != .zero {
            onPan?(translation)
            recognizer.setTranslation(.zero, in: self)
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isPinching = true
            onContinuousZoomBegan?()
            lastPinchScale = recognizer.scale
            let span = Self.touchSpan(from: recognizer, in: self)
            lockedPinchAxis = span.map(Self.axisForOrientation)
        case .changed:
            guard lastPinchScale != 0 else {
                lastPinchScale = recognizer.scale
                return
            }
            if lockedPinchAxis == nil, let span = Self.touchSpan(from: recognizer, in: self) {
                lockedPinchAxis = Self.axisForOrientation(of: span)
            }
            let incrementalScale = recognizer.scale / lastPinchScale
            lastPinchScale = recognizer.scale
            let axis = lockedPinchAxis ?? .horizontal
            if let zoom = ObsPlotZoom.single(axis: axis, scale: incrementalScale) {
                onZoom?(zoom)
            }
        default:
            lastPinchScale = 1
            lockedPinchAxis = nil
            if isPinching {
                isPinching = false
                onContinuousZoomEnded?()
            }
        }
    }

    @objc private func handleReset(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .recognized { onReset?() }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private static let verticalOrientationFactor: CGFloat = 2

    private static func axisForOrientation(of span: ObsPlotTouchSpan) -> ObsPlotZoomAxis {
        span.height > span.width * verticalOrientationFactor ? .vertical : .horizontal
    }

    private static func touchSpan(from recognizer: UIPinchGestureRecognizer, in view: UIView) -> ObsPlotTouchSpan? {
        guard recognizer.numberOfTouches >= 2 else { return nil }
        var points: [CGPoint] = []
        for index in 0..<recognizer.numberOfTouches {
            points.append(recognizer.location(ofTouch: index, in: view))
        }
        return ObsPlotTouchSpan.span(for: points)
    }
}
#endif
