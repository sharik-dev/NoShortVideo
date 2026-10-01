//
//  FloatingDrag.swift
//  No short video
//

import SwiftUI

/// Rend un élément flottant déplaçable au doigt ET touchable, sans que le
/// lâcher d'un déplacement compte comme un appui.
///
/// Un `Button` (ou un `onTapGesture`) posé sous un `DragGesture` simultané
/// déclenche son action au lever du doigt, même après un glissé : la vue suit
/// le doigt, donc le doigt se lève toujours « dedans ». Ici un seul geste
/// tranche à la fin : si le doigt a dépassé le seuil à un moment, c'était un
/// déplacement, sinon c'était un appui.
struct FloatingDrag: ViewModifier {

    @Binding var offset: CGSize
    var onTap: (() -> Void)?

    /// En deçà, un appui qui tremble reste un appui.
    private static let threshold: CGFloat = 8

    @GestureState private var translation: CGSize = .zero
    /// Passe à vrai dès que le doigt dépasse le seuil, et y reste jusqu'au
    /// lever : un aller-retour qui revient près du départ reste un déplacement.
    @State private var dragging = false

    func body(content: Content) -> some View {
        content
            .offset(x: offset.width  + translation.width,
                    y: offset.height + translation.height)
            // Global : la vue se déplace sous le doigt, ses coordonnées
            // locales glisseraient avec elle.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { v in
                        if !dragging, Self.distance(v.translation) > Self.threshold {
                            dragging = true
                        }
                    }
                    .updating($translation) { v, s, _ in
                        if Self.distance(v.translation) > Self.threshold || s != .zero {
                            s = v.translation
                        }
                    }
                    .onEnded { v in
                        defer { dragging = false }
                        if dragging || Self.distance(v.translation) > Self.threshold {
                            offset.width  += v.translation.width
                            offset.height += v.translation.height
                        } else {
                            onTap?()
                        }
                    }
            )
            .accessibilityAddTraits(onTap == nil ? [] : .isButton)
            .accessibilityAction { onTap?() }
    }

    private static func distance(_ t: CGSize) -> CGFloat {
        (t.width * t.width + t.height * t.height).squareRoot()
    }
}

extension View {
    /// Voir `FloatingDrag`.
    func floatingDrag(offset: Binding<CGSize>, onTap: (() -> Void)? = nil) -> some View {
        modifier(FloatingDrag(offset: offset, onTap: onTap))
    }
}
