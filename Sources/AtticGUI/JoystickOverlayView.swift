// JoystickOverlayView.swift
// AtticGUI
//
// A small HUD overlay that displays the current joystick input state.
// Shows a digital direction cross and fire button indicator in the
// bottom-right corner of the emulator display.
//
// The overlay is non-interactive (.allowsHitTesting(false)) and only
// visible when joystick emulation is active (F9) or a physical game
// controller is connected.
//
// Visual design:
// - Direction cross: 4 arrow indicators in a plus pattern
// - Active directions light up bright green, inactive are dim gray
// - Fire button: circle that turns red when pressed
// - Semi-transparent dark background for readability over any screen content

import SwiftUI

// MARK: - JoystickOverlayView

/// Displays a compact joystick state indicator as a HUD overlay.
///
/// Place this in the EmulatorDisplayView's ZStack with `.allowsHitTesting(false)`
/// so it floats over the emulator screen without intercepting input.
///
/// - Parameters:
///   - up/down/left/right: Whether each direction is active.
///   - trigger: Whether the fire button is pressed.
///   - visible: Whether the overlay should be shown at all.
struct JoystickOverlayView: View {
    let up: Bool
    let down: Bool
    let left: Bool
    let right: Bool
    let trigger: Bool
    let visible: Bool

    /// Size of each direction indicator (triangle).
    private let indicatorSize: CGFloat = 14

    /// Spacing between the center and each direction indicator.
    private let indicatorSpacing: CGFloat = 4

    /// Size of the fire button circle.
    private let fireButtonSize: CGFloat = 20

    /// Color for active (pressed) direction indicators.
    private let activeColor = Color.green

    /// Color for inactive (released) direction indicators.
    private let inactiveColor = Color.white.opacity(0.2)

    /// Color for the fire button when pressed.
    private let fireActiveColor = Color.red

    /// Color for the fire button when released.
    private let fireInactiveColor = Color.white.opacity(0.2)

    var body: some View {
        if visible {
            VStack(alignment: .trailing) {
                Spacer()
                HStack(alignment: .bottom) {
                    Spacer()
                    HStack(spacing: 16) {
                        // Direction cross
                        directionCross

                        // Fire button
                        fireButton
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.4))
                    )
                }
                .padding(16)
            }
            // Pass through all mouse/keyboard events to layers beneath
            .allowsHitTesting(false)
        }
    }

    // MARK: - Direction Cross

    /// The four-directional joystick indicator arranged in a plus/cross pattern.
    ///
    /// Uses a ZStack with offset triangles pointing in each cardinal direction.
    /// Active directions are bright green; inactive ones are dim gray.
    private var directionCross: some View {
        // The cross is built as a grid: 3 rows x 3 columns, with indicators
        // at the top-center, middle-left, middle-right, and bottom-center positions.
        let size = indicatorSize * 3 + indicatorSpacing * 2

        return ZStack {
            // Up arrow (top center)
            DirectionTriangle(direction: .up)
                .fill(up ? activeColor : inactiveColor)
                .frame(width: indicatorSize, height: indicatorSize)
                .offset(y: -(indicatorSize + indicatorSpacing))

            // Down arrow (bottom center)
            DirectionTriangle(direction: .down)
                .fill(down ? activeColor : inactiveColor)
                .frame(width: indicatorSize, height: indicatorSize)
                .offset(y: indicatorSize + indicatorSpacing)

            // Left arrow (middle left)
            DirectionTriangle(direction: .left)
                .fill(left ? activeColor : inactiveColor)
                .frame(width: indicatorSize, height: indicatorSize)
                .offset(x: -(indicatorSize + indicatorSpacing))

            // Right arrow (middle right)
            DirectionTriangle(direction: .right)
                .fill(right ? activeColor : inactiveColor)
                .frame(width: indicatorSize, height: indicatorSize)
                .offset(x: indicatorSize + indicatorSpacing)

            // Center dot (indicates the joystick "center" position)
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 6, height: 6)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Fire Button

    /// The fire/trigger button indicator.
    ///
    /// A circle that turns red when pressed, with a "FIRE" label beneath.
    private var fireButton: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(trigger ? fireActiveColor : fireInactiveColor)
                .frame(width: fireButtonSize, height: fireButtonSize)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )

            Text("FIRE")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.5))
        }
    }
}

// MARK: - DirectionTriangle

/// A triangle shape pointing in one of four cardinal directions.
///
/// Used as the individual direction indicators in the joystick cross.
/// Each triangle points outward from the center of the cross pattern.
struct DirectionTriangle: Shape {
    /// The cardinal direction this triangle points toward.
    enum Direction {
        case up, down, left, right
    }

    let direction: Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Draw a triangle pointing in the specified direction.
        // Each triangle fills its bounding rect with one point at the
        // direction edge and two points at the opposite edge's corners.
        switch direction {
        case .up:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .down:
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .left:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview("Joystick Overlay - Idle") {
    ZStack {
        Color.black
        JoystickOverlayView(
            up: false, down: false, left: false, right: false,
            trigger: false, visible: true
        )
    }
    .frame(width: 400, height: 300)
}

#Preview("Joystick Overlay - Up+Right+Fire") {
    ZStack {
        Color.black
        JoystickOverlayView(
            up: true, down: false, left: false, right: true,
            trigger: true, visible: true
        )
    }
    .frame(width: 400, height: 300)
}
