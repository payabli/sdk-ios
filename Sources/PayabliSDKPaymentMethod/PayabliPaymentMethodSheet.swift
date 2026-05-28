import SwiftUI
import UIKit

public enum PayabliPaymentMethodSheetDismissButton: Sendable, Equatable {
    case close
    case back
    case hidden

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

public struct PayabliPaymentMethodSheetConfiguration {
    public var title: String?
    public var subtitle: String?
    public var dismissButton: PayabliPaymentMethodSheetDismissButton
    public var dismissesOnSuccess: Bool
    public var detents: Set<PresentationDetent>
    public var dragIndicatorVisibility: Visibility
    public var contentInsets: EdgeInsets
    public var movesFormHeaderToSheetHeader: Bool
    public var sizesToContentWhenPossible: Bool
    public var expandsToLargeWhenContentDoesNotFit: Bool

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        dismissButton: PayabliPaymentMethodSheetDismissButton = .close,
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
    func payabliPaymentMethodSheet(
        isPresented: Binding<Bool>,
        component: PayabliPaymentMethod,
        configuration: PayabliPaymentMethodFormConfiguration = PayabliPaymentMethodFormConfiguration(),
        sheetConfiguration: PayabliPaymentMethodSheetConfiguration = PayabliPaymentMethodSheetConfiguration(),
        style: PayabliPaymentMethodStyle? = nil,
        onPaymentMethodAdded: @escaping (PayabliStoredPaymentMethod) -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) -> some View {
        sheet(isPresented: isPresented) {
            PayabliPaymentMethodSheetContent(
                isPresented: isPresented,
                component: component,
                configuration: configuration,
                sheetConfiguration: sheetConfiguration,
                style: style,
                onPaymentMethodAdded: onPaymentMethodAdded,
                onError: onError
            )
        }
    }
}

private struct PayabliPaymentMethodSheetContent: View {
    @Binding var isPresented: Bool
    @State private var selectedDetent: PresentationDetent
    @State private var measuredContentHeight: CGFloat = 0
    @State private var largestAvailableSheetHeight: CGFloat = 0

    let component: PayabliPaymentMethod
    let configuration: PayabliPaymentMethodFormConfiguration
    let sheetConfiguration: PayabliPaymentMethodSheetConfiguration
    let style: PayabliPaymentMethodStyle?
    let onPaymentMethodAdded: (PayabliStoredPaymentMethod) -> Void
    let onError: (Error) -> Void

    init(
        isPresented: Binding<Bool>,
        component: PayabliPaymentMethod,
        configuration: PayabliPaymentMethodFormConfiguration,
        sheetConfiguration: PayabliPaymentMethodSheetConfiguration,
        style: PayabliPaymentMethodStyle?,
        onPaymentMethodAdded: @escaping (PayabliStoredPaymentMethod) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        _isPresented = isPresented
        _selectedDetent = State(initialValue: Self.initialDetent(for: sheetConfiguration))
        self.component = component
        self.configuration = configuration
        self.sheetConfiguration = sheetConfiguration
        self.style = style
        self.onPaymentMethodAdded = onPaymentMethodAdded
        self.onError = onError
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sheetHeader

                    PayabliPaymentMethodView(
                        component: component,
                        configuration: formConfiguration,
                        style: style,
                        onPaymentMethodAdded: { method in
                            onPaymentMethodAdded(method)
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
                            key: PayabliPaymentMethodSheetContentHeightKey.self,
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
            .onPreferenceChange(PayabliPaymentMethodSheetContentHeightKey.self) { contentHeight in
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
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sheetConfiguration.dismissButton.accessibilityLabel)
        }
    }

    private var shouldShowHeader: Bool {
        sheetConfiguration.dismissButton != .hidden || sheetTitle != nil || sheetSubtitle != nil
    }

    private var sheetTitle: String? {
        if let configuredTitle = sheetConfiguration.title?.trimmed.nilIfEmpty {
            return configuredTitle
        }
        guard sheetConfiguration.movesFormHeaderToSheetHeader else { return nil }
        return configuration.labels.title.trimmed.nilIfEmpty
    }

    private var sheetSubtitle: String? {
        if let configuredSubtitle = sheetConfiguration.subtitle?.trimmed.nilIfEmpty {
            return configuredSubtitle
        }
        guard sheetConfiguration.movesFormHeaderToSheetHeader else { return nil }
        return configuration.labels.subtitle?.trimmed.nilIfEmpty
    }

    private var formConfiguration: PayabliPaymentMethodFormConfiguration {
        guard sheetConfiguration.movesFormHeaderToSheetHeader else { return configuration }

        var adjusted = configuration
        var labels = adjusted.labels
        labels.title = ""
        labels.subtitle = nil
        adjusted.labels = labels
        return adjusted
    }

    private static func initialDetent(
        for sheetConfiguration: PayabliPaymentMethodSheetConfiguration
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

private struct PayabliPaymentMethodSheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
