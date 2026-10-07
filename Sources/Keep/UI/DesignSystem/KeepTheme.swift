import SwiftUI

enum KeepTheme {
    static let background = Color("Background")
    static let paper = Color("Paper")
    static let surface = Color("Surface")
    static let ink = Color("Foreground")
    static let secondaryInk = Color("SecondaryForeground")
    static let mutedInk = Color("MutedForeground")
    static let mutedWarm = Color("MutedWarm")
    static let highlight = Color("WarmHighlight")
    static let accent = Color("AccentColor")
    static let accentStrong = Color("AccentStrong")
    static let sage = Color("Sage")
    static let sageInk = Color("SageForeground")
    static let mistBlue = Color("MistBlue")
    static let border = Color("Border")
    static let controlBorder = Color("ControlBorder")
    static let focusRing = Color("FocusRing")
    static let taskBothTimerFill = Color("TaskBothTimerFill")
    static let taskBothTimerInk = Color("TaskBothTimerInk")

    static func headingFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let cardRadius: CGFloat = 22
}
