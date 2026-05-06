//
//  ContentView.swift
//  calculator
//
//  Created by Hans Preinfalk on 5/6/26.
//

import SwiftUI

struct ContentView: View {
    @State private var displayText = "0"
    @State private var accumulatedValue: Double?
    @State private var currentTerm: Double?
    @State private var pendingLowOperation: CalculatorOperation?
    @State private var pendingHighOperation: CalculatorOperation?
    @State private var isEnteringNumber = false
    @State private var shouldResetOnNextDigit = false

    private let rows: [[CalculatorButton]] = [
        [.delete, .clear, .percent, .operation(.divide)],
        [.digit(7), .digit(8), .digit(9), .operation(.multiply)],
        [.digit(4), .digit(5), .digit(6), .operation(.subtract)],
        [.digit(1), .digit(2), .digit(3), .operation(.add)],
        [.sign, .digit(0), .decimal, .equals]
    ]

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 18
            let buttonSpacing: CGFloat = 10
            let buttonSize = (geometry.size.width - (horizontalPadding * 2) - (buttonSpacing * 3)) / 4

            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    topBar
                        .padding(.top, 8)

                    Spacer()

                    display

                    VStack(spacing: buttonSpacing) {
                        ForEach(rows, id: \.self) { row in
                            HStack(spacing: buttonSpacing) {
                                ForEach(row, id: \.self) { button in
                                    CalculatorButtonView(
                                        button: button,
                                        size: buttonSize,
                                        label: label(for: button),
                                        isSelected: selectedState(for: button)
                                    ) {
                                        handleTap(button)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            CircleIconButton(systemImage: "clock.arrow.circlepath")
            Spacer()
            CircleIconButton(systemImage: "square.grid.3x3.fill")
        }
    }

    private var display: some View {
        Text(displayText)
            .font(.system(size: 76, weight: .light, design: .default))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.32)
            .padding(.horizontal, 8)
    }

    private func selectedState(for button: CalculatorButton) -> Bool {
        guard case .operation(let operation) = button else { return false }
        return activeOperation == operation && !isEnteringNumber
    }

    private func label(for button: CalculatorButton) -> String {
        switch button {
        case .clear:
            return displayText == "0" && accumulatedValue == nil && currentTerm == nil && activeOperation == nil ? "AC" : "C"
        default:
            return button.title
        }
    }

    private func handleTap(_ button: CalculatorButton) {
        switch button {
        case .digit(let value):
            inputDigit(value)
        case .decimal:
            inputDecimal()
        case .clear:
            clear()
        case .delete:
            deleteLastCharacter()
        case .sign:
            toggleSign()
        case .percent:
            applyPercent()
        case .operation(let operation):
            setOperation(operation)
        case .equals:
            performEquals()
        }
    }

    private func inputDigit(_ digit: Int) {
        if shouldResetOnNextDigit {
            displayText = "0"
            shouldResetOnNextDigit = false
            isEnteringNumber = false
        }

        if shouldApplyImplicitMultiplication(for: digit) {
            applyImplicitMultiplication()
            displayText = "\(digit)"
            isEnteringNumber = true
            return
        }

        if isEnteringNumber {
            if displayText == "0" {
                displayText = "\(digit)"
            } else if displayText == "-0" {
                displayText = "-\(digit)"
            } else if displayText.replacingOccurrences(of: "-", with: "").count < 15 {
                displayText.append("\(digit)")
            }
        } else {
            displayText = "\(digit)"
            isEnteringNumber = true
        }
    }

    private func inputDecimal() {
        if shouldResetOnNextDigit {
            displayText = "0"
            shouldResetOnNextDigit = false
            isEnteringNumber = false
        }

        if shouldApplyImplicitMultiplicationBeforeDecimal {
            applyImplicitMultiplication()
            displayText = "0."
            isEnteringNumber = true
            return
        }

        if !isEnteringNumber {
            displayText = "0."
            isEnteringNumber = true
            return
        }

        guard !displayText.contains(".") else { return }
        displayText.append(".")
    }

    private func clear() {
        if displayText != "0" || isEnteringNumber {
            displayText = "0"
            clearCurrentEntryState()
            return
        }

        accumulatedValue = nil
        currentTerm = nil
        pendingLowOperation = nil
        pendingHighOperation = nil
        shouldResetOnNextDigit = false
    }

    private func deleteLastCharacter() {
        guard displayText != "0" else {
            clearCurrentEntryState()
            return
        }

        shouldResetOnNextDigit = false
        isEnteringNumber = true

        displayText.removeLast()

        if displayText.isEmpty || displayText == "-" {
            displayText = "0"
            clearCurrentEntryState()
        }
    }

    private func toggleSign() {
        guard let value = currentValue else { return }
        setDisplay(to: value == 0 ? 0 : -value)
        isEnteringNumber = true
    }

    private func applyPercent() {
        guard let value = currentValue else { return }

        let result = value / 100

        setDisplay(to: result)
        isEnteringNumber = true
    }

    private func setOperation(_ operation: CalculatorOperation) {
        guard let value = currentValue else { return }

        switch operation.precedence {
        case .low:
            let termResult = resolveCurrentTerm(with: value)

            if let pendingLowOperation, let accumulatedValue {
                self.accumulatedValue = pendingLowOperation.apply(lhs: accumulatedValue, rhs: termResult)
            } else {
                accumulatedValue = termResult
            }

            currentTerm = nil
            pendingHighOperation = nil
            pendingLowOperation = operation
        case .high:
            if let pendingHighOperation, let currentTerm, isEnteringNumber {
                self.currentTerm = pendingHighOperation.apply(lhs: currentTerm, rhs: value)
            } else if currentTerm == nil || isEnteringNumber {
                currentTerm = value
            }

            pendingHighOperation = operation
        }

        shouldResetOnNextDigit = true
        isEnteringNumber = false
    }

    private func performEquals() {
        guard let value = currentValue else { return }

        let termResult = resolveCurrentTerm(with: value)
        let result: Double

        if let pendingLowOperation, let accumulatedValue {
            result = pendingLowOperation.apply(lhs: accumulatedValue, rhs: termResult)
        } else {
            result = termResult
        }

        setDisplay(to: result)
        accumulatedValue = nil
        currentTerm = nil
        pendingLowOperation = nil
        pendingHighOperation = nil
        shouldResetOnNextDigit = true
        isEnteringNumber = false
    }

    private var currentValue: Double? {
        Double(displayText.replacingOccurrences(of: ",", with: ""))
    }

    private func setDisplay(to value: Double) {
        if value.isNaN || value.isInfinite {
            displayText = "Error"
            accumulatedValue = nil
            currentTerm = nil
            pendingLowOperation = nil
            pendingHighOperation = nil
            shouldResetOnNextDigit = true
            isEnteringNumber = false
            return
        }

        displayText = NumberFormatter.displayFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private var activeOperation: CalculatorOperation? {
        pendingHighOperation ?? pendingLowOperation
    }

    private func clearCurrentEntryState() {
        isEnteringNumber = false
        shouldResetOnNextDigit = false
        pendingLowOperation = nil
        pendingHighOperation = nil
        currentTerm = nil
    }

    private func shouldApplyImplicitMultiplication(for digit: Int) -> Bool {
        digit != 0
            && pendingHighOperation == .multiply
            && currentTerm != nil
            && isEnteringNumber
            && displayText == "0"
    }

    private var shouldApplyImplicitMultiplicationBeforeDecimal: Bool {
        pendingHighOperation == .multiply
            && currentTerm != nil
            && isEnteringNumber
            && displayText == "0"
    }

    private func applyImplicitMultiplication() {
        guard pendingHighOperation == .multiply,
              let currentTerm,
              let currentValue else { return }

        self.currentTerm = CalculatorOperation.multiply.apply(lhs: currentTerm, rhs: currentValue)
        shouldResetOnNextDigit = false
        isEnteringNumber = false
    }

    private func resolveCurrentTerm(with value: Double) -> Double {
        guard let pendingHighOperation, let currentTerm else { return value }
        return pendingHighOperation.apply(lhs: currentTerm, rhs: value)
    }
}

private enum CalculatorOperation: String, Hashable {
    case divide = "÷"
    case multiply = "×"
    case subtract = "−"
    case add = "+"

    var precedence: OperationPrecedence {
        switch self {
        case .add, .subtract:
            return .low
        case .multiply, .divide:
            return .high
        }
    }

    func apply(lhs: Double, rhs: Double) -> Double {
        switch self {
        case .divide:
            return lhs / rhs
        case .multiply:
            return lhs * rhs
        case .subtract:
            return lhs - rhs
        case .add:
            return lhs + rhs
        }
    }
}

private enum OperationPrecedence {
    case low
    case high
}

private enum CalculatorButton: Hashable {
    case digit(Int)
    case decimal
    case clear
    case delete
    case sign
    case percent
    case operation(CalculatorOperation)
    case equals

    var title: String {
        switch self {
        case .digit(let value):
            return "\(value)"
        case .decimal:
            return "."
        case .clear:
            return ""
        case .delete:
            return ""
        case .sign:
            return "+/-"
        case .percent:
            return "%"
        case .operation(let operation):
            return operation.rawValue
        case .equals:
            return "="
        }
    }

    var systemImage: String? {
        switch self {
        case .delete:
            return "delete.left"
        default:
            return nil
        }
    }

    var backgroundColor: Color {
        switch self {
        case .clear, .delete, .percent:
            return Color(red: 0.49, green: 0.49, blue: 0.5)
        case .operation, .equals:
            return Color(red: 0.98, green: 0.64, blue: 0.18)
        case .digit, .decimal, .sign:
            return Color(red: 0.2, green: 0.2, blue: 0.21)
        }
    }

    var pressedBackgroundColor: Color {
        switch self {
        case .clear, .delete, .percent:
            return Color(red: 0.72, green: 0.72, blue: 0.74)
        case .operation, .equals:
            return Color(red: 0.99, green: 0.77, blue: 0.33)
        case .digit, .decimal, .sign:
            return Color(red: 0.58, green: 0.58, blue: 0.6)
        }
    }

    var glassTintColor: Color {
        switch self {
        case .clear, .delete, .percent:
            return Color.white.opacity(0.3)
        case .operation, .equals:
            return Color.orange.opacity(0.72)
        case .digit, .decimal, .sign:
            return Color.white.opacity(0.12)
        }
    }

    var pressedGlassTintColor: Color {
        switch self {
        case .clear, .delete, .percent:
            return Color.white.opacity(0.5)
        case .operation, .equals:
            return Color.orange.opacity(0.9)
        case .digit, .decimal, .sign:
            return Color.white.opacity(0.28)
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .operation:
            return 37
        case .equals:
            return 34
        case .digit, .decimal, .sign, .clear, .percent:
            return 30
        case .delete:
            return 26
        }
    }
}

private struct CalculatorButtonView: View {
    let button: CalculatorButton
    let size: CGFloat
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EmptyView()
        }
        .buttonStyle(
            CalculatorPressStyle(
                button: button,
                size: size,
                label: label,
                isSelected: isSelected
            )
        )
    }
}

private struct CircleIconButton: View {
    let systemImage: String

    var body: some View {
        Button {
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct CalculatorPressStyle: ButtonStyle {
    let button: CalculatorButton
    let size: CGFloat
    let label: String
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .fill(backgroundColor(isPressed: configuration.isPressed).opacity(0.55))

            if let systemImage = button.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: button.fontSize, weight: .medium))
                    .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            } else {
                Text(label)
                    .font(.system(size: button.fontSize, weight: .regular, design: .default))
                    .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            }
        }
        .frame(width: size, height: size)
        .glassEffect(glassStyle(isPressed: configuration.isPressed), in: Circle())
        .contentShape(Circle())
        .scaleEffect(configuration.isPressed ? 1.11 : 1)
        .zIndex(configuration.isPressed ? 1 : 0)
        .animation(.easeOut(duration: 0.17), value: configuration.isPressed)
        .animation(.linear(duration: 0.04), value: isSelected)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return button.pressedBackgroundColor
        }

        if isSelected {
            return .white
        }

        return button.backgroundColor
    }

    private func glassStyle(isPressed: Bool) -> Glass {
        let tint: Color

        if isPressed {
            tint = button.pressedGlassTintColor
        } else if isSelected {
            tint = .white.opacity(0.95)
        } else {
            tint = button.glassTintColor
        }

        return .regular.tint(tint).interactive()
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return .orange
        }

        return .white
    }
}

private extension NumberFormatter {
    static let displayFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }()
}

#Preview {
    ContentView()
}
