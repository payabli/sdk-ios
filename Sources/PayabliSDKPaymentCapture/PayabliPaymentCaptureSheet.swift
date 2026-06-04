import PayabliSDKPaymentMethod
import SwiftUI
import UIKit

public extension View {
    func payabliPaymentCaptureSheet(
        isPresented: Binding<Bool>,
        component: PayabliPaymentCapture,
        configuration: PayabliPaymentCaptureFormConfiguration = PayabliPaymentCaptureFormConfiguration(),
        sheetConfiguration: PayabliPaymentCaptureSheetConfiguration = PayabliPaymentCaptureSheetConfiguration(),
        style: PayabliPaymentCaptureStyle? = nil,
        onPaymentCaptured: @escaping (PayabliPaymentCaptureResult) -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) -> some View {
        sheet(isPresented: isPresented) {
            PayabliPaymentCaptureSheetContent(
                isPresented: isPresented,
                component: component,
                configuration: configuration,
                sheetConfiguration: sheetConfiguration,
                style: style,
                onPaymentCaptured: onPaymentCaptured,
                onError: onError
            )
        }
    }
}

struct PayabliPaymentCaptureSheetContent: View {
    @Binding var isPresented: Bool
    @State private var selectedDetent: PresentationDetent
    @State private var measuredContentHeight: CGFloat = 0
    @State private var largestAvailableSheetHeight: CGFloat = 0

    let component: PayabliPaymentCapture
    let configuration: PayabliPaymentCaptureFormConfiguration
    let sheetConfiguration: PayabliPaymentCaptureSheetConfiguration
    let style: PayabliPaymentCaptureStyle?
    let onPaymentCaptured: (PayabliPaymentCaptureResult) -> Void
    let onError: (Error) -> Void

    init(
        isPresented: Binding<Bool>,
        component: PayabliPaymentCapture,
        configuration: PayabliPaymentCaptureFormConfiguration,
        sheetConfiguration: PayabliPaymentCaptureSheetConfiguration,
        style: PayabliPaymentCaptureStyle?,
        onPaymentCaptured: @escaping (PayabliPaymentCaptureResult) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        _isPresented = isPresented
        _selectedDetent = State(initialValue: Self.initialDetent(for: sheetConfiguration))
        self.component = component
        self.configuration = configuration
        self.sheetConfiguration = sheetConfiguration
        self.style = style
        self.onPaymentCaptured = onPaymentCaptured
        self.onError = onError
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sheetHeader

                    PayabliPaymentCaptureView(
                        component: component,
                        configuration: formConfiguration,
                        style: style,
                        onPaymentCaptured: { result in
                            onPaymentCaptured(result)
                            if sheetConfiguration.dismissesOnSuccess {
                                isPresented = false
                            }
                        },
                        onError: onError
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
                            key: CaptureSheetContentHeightKey.self,
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
            .onPreferenceChange(CaptureSheetContentHeightKey.self) { contentHeight in
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
        if let systemImageName = sheetConfiguration.dismissButton.captureSystemImageName {
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
            .accessibilityLabel(sheetConfiguration.dismissButton.captureAccessibilityLabel)
        }
    }

    private var shouldShowHeader: Bool {
        sheetConfiguration.dismissButton != .hidden || sheetTitle != nil || sheetSubtitle != nil
    }

    private var sheetTitle: String? {
        if let configuredTitle = sheetConfiguration.title?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty {
            return configuredTitle
        }
        guard sheetConfiguration.movesFormHeaderToSheetHeader else { return nil }
        return configuration.labels.title.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    private var sheetSubtitle: String? {
        if let configuredSubtitle = sheetConfiguration.subtitle?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty {
            return configuredSubtitle
        }
        guard sheetConfiguration.movesFormHeaderToSheetHeader else { return nil }
        return configuration.labels.subtitle?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    private var formConfiguration: PayabliPaymentCaptureFormConfiguration {
        guard sheetConfiguration.movesFormHeaderToSheetHeader else { return configuration }

        let labels = PayabliPaymentCaptureLabels(
            title: "",
            subtitle: nil,
            submitButton: configuration.labels.submitButton,
            fieldLabels: configuration.labels.fieldLabels,
            fieldPlaceholders: configuration.labels.fieldPlaceholders
        )
        return PayabliPaymentCaptureFormConfiguration(
            allowedMethods: configuration.allowedMethods,
            defaultMethod: configuration.defaultMethod,
            cardFieldOrder: configuration.cardFieldOrder,
            achFieldOrder: configuration.achFieldOrder,
            cardSections: configuration.cardSections,
            achSections: configuration.achSections,
            hiddenValues: configuration.hiddenValues,
            options: configuration.options,
            labels: labels,
            labelLayout: configuration.labelLayout,
            showsFieldLabels: configuration.showsFieldLabels,
            hiddenFieldLabels: configuration.hiddenFieldLabels,
            formatting: configuration.formatting,
            inputSizing: configuration.inputSizing,
            cardBrandIconPlacement: configuration.cardBrandIconPlacement,
            errorMessagePlacement: configuration.errorMessagePlacement,
            requiredFields: configuration.requiredFields,
            paymentSummary: configuration.paymentSummary
        )
    }

    private static func initialDetent(
        for sheetConfiguration: PayabliPaymentCaptureSheetConfiguration
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

private struct CaptureSheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension PayabliPaymentCaptureSheetDismissButton {
    var captureSystemImageName: String? {
        switch self {
        case .close:
            return "xmark"
        case .back:
            return "chevron.left"
        case .hidden:
            return nil
        }
    }

    var captureAccessibilityLabel: String {
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
