import SwiftUI

/// Draws one of the app's three surfaces behind whatever it is applied to.
///
/// Applied through `View.chromePanel(_:)` rather than directly, so a call site reads as the
/// name of the surface it is asking for.
struct ChromePanel: ViewModifier {
    /// Which surface to draw.
    let style: ChromePanelStyle

    func body(content: Content) -> some View {
        let panel = content
            .background(fill)
            .clipShape(shape)
            .overlay { shape.strokeBorder(stroke, lineWidth: 1) }
        switch style {
        case .floating:
            panel.shadow(
                color: .black.opacity(ZephraChrome.shadowOpacity),
                radius: ZephraChrome.shadowRadius,
                y: ZephraChrome.shadowY
            )
        case .inset, .warning:
            panel
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private var radius: CGFloat {
        switch style {
        case .floating: ZephraChrome.capsuleRadius
        case .inset, .warning: ZephraChrome.cardRadius
        }
    }

    private var fill: AnyShapeStyle {
        switch style {
        case .floating: AnyShapeStyle(.regularMaterial)
        case .inset: AnyShapeStyle(.quaternary)
        case .warning: AnyShapeStyle(ZephraChrome.warningWash)
        }
    }

    private var stroke: AnyShapeStyle {
        switch style {
        case .floating: AnyShapeStyle(ZephraChrome.hairline)
        case .inset: AnyShapeStyle(Color.clear)
        case .warning: AnyShapeStyle(ZephraChrome.warningStroke)
        }
    }
}

extension View {
    /// Puts one of the app's three surfaces behind this view.
    func chromePanel(_ style: ChromePanelStyle) -> some View {
        modifier(ChromePanel(style: style))
    }
}

#Preview("Panels") {
    VStack(spacing: 16) {
        Text("Floating").padding(14).chromePanel(.floating)
        Text("Inset").padding(14).chromePanel(.inset)
        Text("Warning").padding(14).chromePanel(.warning)
    }
    .padding(30)
    .frame(width: 320)
    .background(Color.canvasBackground)
}
