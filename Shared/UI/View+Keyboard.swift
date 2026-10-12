//
//  View+Keyboard.swift
//  DuGo-iOS
//
//  Created by 김승원 on 1/10/26.
//

import SwiftUI
import UIKit

private struct DismissKeyboardOnBackgroundTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                KeyboardDismissTapInstaller()
                    .frame(width: 0, height: 0)
            }
    }
}

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WindowObservationView {
        let view = WindowObservationView()
        view.isUserInteractionEnabled = false
        view.onWindowChange = context.coordinator.installGestureRecognizer
        return view
    }

    func updateUIView(_ uiView: WindowObservationView, context: Context) {
        context.coordinator.installGestureRecognizer(in: uiView.window)
    }

    static func dismantleUIView(_ uiView: WindowObservationView, coordinator: Coordinator) {
        coordinator.removeGestureRecognizer()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(
                target: self,
                action: #selector(dismissKeyboard)
            )
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        func installGestureRecognizer(in window: UIWindow?) {
            guard self.window !== window else { return }

            removeGestureRecognizer()
            self.window = window
            window?.addGestureRecognizer(tapGestureRecognizer)
        }

        func removeGestureRecognizer() {
            window?.removeGestureRecognizer(tapGestureRecognizer)
            window = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            !touch.isInsideTextInput
        }

        @objc private func dismissKeyboard() {
            window?.endEditing(true)
        }
    }
}

private final class WindowObservationView: UIView {
    var onWindowChange: ((UIWindow?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window)
    }
}

private extension UITouch {
    var isInsideTextInput: Bool {
        var currentView = view

        while let inspectedView = currentView {
            if inspectedView is UITextField || inspectedView is UITextView {
                return true
            }

            currentView = inspectedView.superview
        }

        return false
    }
}

extension View {
    func dismissKeyboardOnBackgroundTap() -> some View {
        modifier(DismissKeyboardOnBackgroundTapModifier())
    }
}
