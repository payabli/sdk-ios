import PayabliSDKCore
import SwiftUI
import UIKit

public enum PayabliPayInSheetDismissButton: Sendable, Equatable {
    case close
    case back
    case hidden
}

public struct PayabliPayInSheetConfiguration {
    public let title: String?
    public let subtitle: String?
    public let dismissButton: PayabliPayInSheetDismissButton
    public let dismissesOnSuccess: Bool
    public let detents: Set<PresentationDetent>
    public let dragIndicatorVisibility: Visibility
    public let contentInsets: EdgeInsets
    public let movesFormHeaderToSheetHeader: Bool
    public let sizesToContentWhenPossible: Bool
    public let expandsToLargeWhenContentDoesNotFit: Bool

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        dismissButton: PayabliPayInSheetDismissButton = .close,
        dismissesOnSuccess: Bool = true,
        detents: Set<PresentationDetent> = [.medium, .large],
        dragIndicatorVisibility: Visibility = .visible,
        contentInsets: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 24, trailing: 20),
        movesFormHeaderToSheetHeader: Bool = true,
        sizesToContentWhenPossible: Bool = true,
        expandsToLargeWhenContentDoesNotFit: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
        self.dismissButton = dismissButton
        self.dismissesOnSuccess = dismissesOnSuccess
        self.detents = detents.isEmpty ? [.large] : detents
        self.dragIndicatorVisibility = dragIndicatorVisibility
        self.contentInsets = contentInsets
        self.movesFormHeaderToSheetHeader = movesFormHeaderToSheetHeader
        self.sizesToContentWhenPossible = sizesToContentWhenPossible
        self.expandsToLargeWhenContentDoesNotFit = expandsToLargeWhenContentDoesNotFit
    }
}

public extension View {
    /// Presents the form in a sheet, bound to one operation of a component.
    ///
    /// - Parameters:
    ///   - isPresented: whether the sheet is shown.
    ///   - payIn: the component the form submits through.
    ///   - operation: the one operation the form submits.
    ///   - configuration: the fields the form draws and how they behave.
    ///   - labels: the wording the form draws; what is absent or blank falls back to the SDK's own.
    ///   - sheetConfiguration: how the sheet itself is presented.
    ///   - style: the colors, fonts and spacing the form draws with, nil to read the environment's.
    ///   - onCompleted: called once with the outcome of the submission: `.method` for a stored payment
    ///     method, `.payment` for a transaction.
    ///   - onFailed: called with the failure the flow threw, unchanged, when a submission the form
    ///     sent did not complete.
    ///   - onMethodChanged: called when the drawn method changes: the payer's choice, or the
    ///     configuration withdrawing the method the payer had chosen. Not called for the method the
    ///     form opens with.
    func payabliPayInSheet(
        isPresented: Binding<Bool>,
        payIn: PayabliPayIn,
        operation: PayabliPayInOperation,
        configuration: PayabliPayInFormConfiguration = PayabliPayInFormConfiguration(),
        labels: PayabliPayInFormLabels = PayabliPayInFormLabels(),
        sheetConfiguration: PayabliPayInSheetConfiguration = PayabliPayInSheetConfiguration(),
        style: PayabliPayInFormStyle? = nil,
        onCompleted: @escaping (PayabliPayInFormSuccess) -> Void,
        onFailed: @escaping (any PayabliError) -> Void,
        onMethodChanged: @escaping (PayabliPayInMethodType) -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            PayabliPayInSheetContent(
                isPresented: isPresented,
                payIn: payIn,
                operation: operation,
                configuration: configuration,
                labels: labels,
                sheetConfiguration: sheetConfiguration,
                style: style,
                onCompleted: onCompleted,
                onFailed: onFailed,
                onMethodChanged: onMethodChanged
            )
        }
    }
}

struct PayabliPayInSheetContent: View {
    @Binding var isPresented: Bool
    @State private var selectedDetent: PresentationDetent
    @State private var measuredContentHeight: CGFloat = 0
    @State private var largestAvailableSheetHeight: CGFloat = 0

    let payIn: PayabliPayIn
    let operation: PayabliPayInOperation
    let configuration: PayabliPayInFormConfiguration
    let labels: PayabliPayInFormLabels
    let sheetConfiguration: PayabliPayInSheetConfiguration
    let style: PayabliPayInFormStyle?
    let onCompleted: (PayabliPayInFormSuccess) -> Void
    let onFailed: (any PayabliError) -> Void
    let onMethodChanged: (PayabliPayInMethodType) -> Void

    init(
        isPresented: Binding<Bool>,
        payIn: PayabliPayIn,
        operation: PayabliPayInOperation,
        configuration: PayabliPayInFormConfiguration,
        labels: PayabliPayInFormLabels,
        sheetConfiguration: PayabliPayInSheetConfiguration,
        style: PayabliPayInFormStyle?,
        onCompleted: @escaping (PayabliPayInFormSuccess) -> Void,
        onFailed: @escaping (any PayabliError) -> Void,
        onMethodChanged: @escaping (PayabliPayInMethodType) -> Void
    ) {
        _isPresented = isPresented
        _selectedDetent = State(initialValue: Self.initialDetent(for: sheetConfiguration))
        self.payIn = payIn
        self.operation = operation
        self.configuration = configuration
        self.labels = labels
        self.sheetConfiguration = sheetConfiguration
        self.style = style
        self.onCompleted = onCompleted
        self.onFailed = onFailed
        self.onMethodChanged = onMethodChanged
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sheetHeader

                    PayabliPayInForm(
                        payIn: payIn,
                        operation: operation,
                        configuration: configuration,
                        labels: formLabels,
                        style: style,
                        onCompleted: { success in
                            onCompleted(success)
                            if sheetConfiguration.dismissesOnSuccess {
                                isPresented = false
                            }
                        },
                        onFailed: onFailed,
                        onMethodChanged: onMethodChanged
                    )
                    .transaction { transaction in
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
                .padding(sheetConfiguration.contentInsets)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { contentProxy in
                        Color.clear.preference(
                            key: PayInPaymentFlowSheetContentHeightKey.self,
                            value: contentProxy.size.height
                        )
                    }
                )
            }
            .onAppear {
                recordAvailableSheetHeight(from: proxy)
            }
            .onChange(of: proxy.size.height) { _ in
                recordAvailableSheetHeight(from: proxy)
            }
            .onPreferenceChange(PayInPaymentFlowSheetContentHeightKey.self) { contentHeight in
                updateMeasuredContentHeight(contentHeight)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .presentationDetents(effectiveDetents, selection: $selectedDetent)
        .presentationDragIndicator(sheetConfiguration.dragIndicatorVisibility)
    }

    @ViewBuilder
    private var sheetHeader: some View {
        if shouldShowHeader {
            HStack(alignment: .top, spacing: 12) {
                if sheetConfiguration.dismissButton == .back {
                    dismissButton
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let title = sheetTitle {
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }

                    if let subtitle = sheetSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if sheetConfiguration.dismissButton == .close {
                    dismissButton
                }
            }
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        if let systemImageName = sheetConfiguration.dismissButton.systemImageName {
            Button {
                isPresented = false
            } label: {
                Image(systemName: systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .frame(width: minimumTouchTarget, height: minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sheetConfiguration.dismissButton.accessibilityLabel)
        }
    }

    private var shouldShowHeader: Bool {
        sheetConfiguration.dismissButton != .hidden || sheetTitle != nil || sheetSubtitle != nil
    }

    var sheetTitle: String? {
        if let configuredTitle = sheetConfiguration.title?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty {
            return configuredTitle
        }
        guard sheetConfiguration.movesFormHeaderToSheetHeader else { return nil }
        return labels.drawnTitle
    }

    var sheetSubtitle: String? {
        if let configuredSubtitle = sheetConfiguration.subtitle?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty {
            return configuredSubtitle
        }
        guard sheetConfiguration.movesFormHeaderToSheetHeader else { return nil }
        return labels.subtitle?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    /// The labels the form inside the sheet draws: the sheet's header owns the form's heading when
    /// the configuration moves it there, so the form draws no heading of its own.
    var formLabels: PayabliPayInFormLabels {
        guard sheetConfiguration.movesFormHeaderToSheetHeader else { return labels }

        return PayabliPayInFormLabels(
            title: nil,
            subtitle: nil,
            submitButton: labels.submitButton,
            fieldLabels: labels.fieldLabels,
            fieldPlaceholders: labels.fieldPlaceholders,
            total: labels.total,
            declinedMessage: labels.declinedMessage,
            retryLaterMessage: labels.retryLaterMessage,
            outcomeUnknownMessage: labels.outcomeUnknownMessage,
            otherMessage: labels.otherMessage
        )
    }

    private static func initialDetent(
        for sheetConfiguration: PayabliPayInSheetConfiguration
    ) -> PresentationDetent {
        if sheetConfiguration.detents.contains(.medium) {
            return .medium
        }
        if sheetConfiguration.detents.contains(.large) {
            return .large
        }
        return sheetConfiguration.detents.first ?? .large
    }

    private var effectiveDetents: Set<PresentationDetent> {
        var detents = sheetConfiguration.detents
        if let contentSizedDetent {
            detents.insert(contentSizedDetent)
        }
        return detents
    }

    private var contentSizedDetent: PresentationDetent? {
        guard sheetConfiguration.sizesToContentWhenPossible else { return nil }

        let measuredHeight = ceil(measuredContentHeight)
        guard measuredHeight > 0,
              measuredHeight <= maximumContentDetentHeight
        else {
            return nil
        }

        return .height(measuredHeight)
    }

    private var maximumContentDetentHeight: CGFloat {
        max(0, largestAvailableSheetHeight - 24)
    }

    private var contentHeightUpdateTolerance: CGFloat {
        56
    }

    private var minimumTouchTarget: CGFloat {
        44
    }

    private func updateMeasuredContentHeight(_ contentHeight: CGFloat) {
        let roundedHeight = ceil(contentHeight)
        guard roundedHeight > 0 else { return }

        if measuredContentHeight > 0,
           abs(roundedHeight - measuredContentHeight) < contentHeightUpdateTolerance
        {
            return
        }

        measuredContentHeight = roundedHeight
        updateSelectedDetent()
    }

    private func recordAvailableSheetHeight(from proxy: GeometryProxy) {
        let verticalSafeArea = proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        let availableHeight = max(0, proxy.size.height - verticalSafeArea)
        guard availableHeight > 0 else { return }

        let shouldRecordHeight = selectedDetent == .large || availableHeight > largestAvailableSheetHeight
        guard shouldRecordHeight else {
            updateSelectedDetent()
            return
        }

        guard abs(availableHeight - largestAvailableSheetHeight) >= 1 else {
            updateSelectedDetent()
            return
        }

        largestAvailableSheetHeight = availableHeight
        updateSelectedDetent()
    }

    private func updateSelectedDetent() {
        if let contentSizedDetent {
            guard selectedDetent != contentSizedDetent else { return }
            setSelectedDetent(contentSizedDetent)
            return
        }

        guard sheetConfiguration.expandsToLargeWhenContentDoesNotFit,
              sheetConfiguration.detents.contains(.large),
              selectedDetent != .large,
              measuredContentHeight > maximumContentDetentHeight
        else {
            return
        }

        setSelectedDetent(.large)
    }

    private func setSelectedDetent(_ detent: PresentationDetent) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedDetent = detent
        }
    }
}

private struct PayInPaymentFlowSheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension PayabliPayInSheetDismissButton {
    var systemImageName: String? {
        switch self {
        case .close:
            return "xmark"
        case .back:
            return "chevron.left"
        case .hidden:
            return nil
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .close:
            return "Close"
        case .back:
            return "Back"
        case .hidden:
            return ""
        }
    }
}
