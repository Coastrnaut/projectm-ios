// UITestAccessibilityActionProbe.swift — ACC-005-T11: lets VoiceOverParameterUITests invoke a slider's
// accessibility increment and decrement on iOS. DEBUG builds only, and only with the launch argument
// `-uitestAccessibilityActions`; Release builds contain none of this.
//
// XCTest's `XCUIElement.increment()`/`decrement()` exist only on macOS, and on iOS
// `adjust(toNormalizedSliderPosition:)` drags by touch, never reaching the adjustable action. So each
// accessible slider gets two tiny probe buttons ("<id>.uitestIncrement", "<id>.uitestDecrement").
// A tap finds the slider's element in the window's accessibility tree by its identifier and calls
// `accessibilityIncrement()` / `accessibilityDecrement()` on it: the public UIAccessibility entry
// points VoiceOver's swipe up and down call. The probe never calls the app's closure directly, so the
// test exercises SwiftUI's accessibility bridge and the app's `.accessibilityAdjustableAction`.
// Simulator results are never device evidence.
#if DEBUG
import SwiftUI
import UIKit

enum UITestAccessibilityActionProbe {
    static let argument = "-uitestAccessibilityActions"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

    /// Calls the accessibility increment (or decrement) of the on-screen adjustable element with
    /// `identifier`; returns "performed …" or "missing …" with what was found (the probe's value).
    @MainActor
    static func perform(_ direction: ParameterStepDirection, on identifier: String) -> String {
        var matches: [NSObject] = []
        var visited: Int = 0
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where !window.isHidden {
                collect(identifier, in: window, depth: 0, visited: &visited, into: &matches)
            }
        }
        let onScreen: [NSObject] = matches.filter(isOnScreen)
        let summary: String = matches.map { (match: NSObject) -> String in
            let type: String = String(describing: Swift.type(of: match))
            return type + (isOnScreen(match) ? " on screen" : " off screen")
        }.joined(separator: ", ")
        guard let element = onScreen.first else { return "missing after \(visited): " + summary }
        switch direction {
        case .increment: element.accessibilityIncrement()
        case .decrement: element.accessibilityDecrement()
        }
        return "performed on " + summary
    }

    /// Whether the element is in a visible window and its accessibility frame is on the screen.
    @MainActor
    private static func isOnScreen(_ object: NSObject) -> Bool {
        if let view = object as? UIView, view.window == nil || view.isHidden { return false }
        let frame: CGRect = object.accessibilityFrame
        guard frame.width > 0, frame.height > 0 else { return false }
        let bounds: CGRect = UIApplication.shared.connectedScenes
            .compactMap { (scene: UIScene) -> CGRect? in (scene as? UIWindowScene)?.screen.bounds }.first ?? .zero
        return bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    /// Depth-first search of the accessibility tree (views' subviews and accessibility children).
    @MainActor
    private static func collect(_ identifier: String, in object: NSObject, depth: Int, visited: inout Int,
                                into matches: inout [NSObject]) {
        guard depth < 80 else { return }
        visited += 1
        if accessibilityID(of: object) == identifier, object.accessibilityTraits.contains(.adjustable),
           !matches.contains(where: { (match: NSObject) -> Bool in match === object }) {
            matches.append(object)
        }
        for child in children(of: object) {
            collect(identifier, in: child, depth: depth + 1, visited: &visited, into: &matches)
        }
    }

    @MainActor
    private static func accessibilityID(of object: NSObject) -> String? {
        if let view = object as? UIView { return view.accessibilityIdentifier }
        if let element = object as? UIAccessibilityElement { return element.accessibilityIdentifier }
        if let identified = object as? UIAccessibilityIdentification { return identified.accessibilityIdentifier }
        // SwiftUI's accessibility elements answer the public getter without declaring the protocol.
        let getter: Selector = #selector(getter: UIAccessibilityIdentification.accessibilityIdentifier)
        guard object.responds(to: getter) else { return nil }
        return object.perform(getter)?.takeUnretainedValue() as? String
    }

    @MainActor
    private static func children(of object: NSObject) -> [NSObject] {
        var result: [NSObject] = []
        if let elements = object.accessibilityElements {
            result += elements.compactMap { (element: Any) -> NSObject? in element as? NSObject }
        } else {
            let count: Int = object.accessibilityElementCount()
            if count > 0 && count != NSNotFound {
                for index in 0..<count {
                    if let element = object.accessibilityElement(at: index) as? NSObject { result.append(element) }
                }
            }
        }
        if let view = object as? UIView { result += view.subviews }
        return result
    }
}

/// The two probe buttons beside an accessible slider.
struct UITestAccessibilityActionButtons: View {
    let identifier: String
    @State private var result = ""

    var body: some View {
        HStack(spacing: 2) {
            probe(.decrement, suffix: ".uitestDecrement", symbol: "minus")
            probe(.increment, suffix: ".uitestIncrement", symbol: "plus")
        }
    }

    private func probe(_ direction: ParameterStepDirection, suffix: String, symbol: String) -> some View {
        let id: String = identifier + suffix
        return Button {
            result = UITestAccessibilityActionProbe.perform(direction, on: identifier)
        } label: {
            Image(systemName: symbol).font(.system(size: 9)).frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(id)
        .accessibilityValue(result)
        .accessibilityIdentifier(id)
    }
}
#endif
