import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension View {
  func keyboardDoneToolbar(buttonTitle: String = "Fertig") -> some View {
    toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(buttonTitle) {
          hideSystemKeyboard()
        }
      }
    }
  }

  func dismissKeyboardOnTap() -> some View {
    simultaneousGesture(
      TapGesture().onEnded {
        hideSystemKeyboard()
      }
    )
  }
}

@MainActor
func hideSystemKeyboard() {
  #if canImport(UIKit)
  UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  #endif
}
