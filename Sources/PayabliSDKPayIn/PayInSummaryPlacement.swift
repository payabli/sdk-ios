import Foundation

/// A section as it is drawn: inputs, or the summary with the rows it shows.
struct PayInDrawnSection {
    struct Row: Equatable {
        let field: PayabliPayInField
        let amount: Decimal
    }

    let section: PayabliPayInFieldSection
    let rows: [Row]
    let total: Decimal?

    var isSummary: Bool {
        section.style == .summary
    }

    /// The heading drawn over the section. A summary without a title of its own reads "Payment".
    var title: String? {
        section.title ?? (isSummary ? "Payment" : nil)
    }
}

enum PayInSummaryPlacement {
    static let amountFields: [PayabliPayInField] = [.amount, .serviceFee, .surchargeFee]

    /// The summary section that is drawn: the last one listed. An earlier one draws nothing.
    static func drawnSummaryIndex(in sections: [PayabliPayInFieldSection]) -> Int? {
        sections.lastIndex { $0.style == .summary }
    }

    /// `sections` with every amount that has a figure placed in one summary.
    ///
    /// A host's summary decides where the rows go and what the section is called, never which figures appear:
    /// they follow the order it lists them, then any it left out. A money field listed in an inputs section is
    /// drawn in the summary instead. Of several summary sections only the last is drawn. With no summary section
    /// one is appended after the inputs, and with no figure to show no summary is drawn.
    static func place(
        _ sections: [PayabliPayInFieldSection],
        paymentDetails: PayabliPayInPaymentDetails?,
        showsBaseAmount: Bool
    ) -> [PayInDrawnSection] {
        let inputs = sections.compactMap { section -> PayInDrawnSection? in
            guard section.style == .inputs else { return nil }
            let fields = section.fields.filter { !amountFields.contains($0) }
            guard !fields.isEmpty else { return nil }
            return PayInDrawnSection(section: section.replacingFields(fields), rows: [], total: nil)
        }

        let figures: [PayabliPayInField: Decimal] = amountFields.reduce(into: [:]) { result, field in
            if field == .amount, !showsBaseAmount {
                return
            }
            result[field] = PayabliPayInSummaryRows.rowAmount(for: field, paymentDetails: paymentDetails)
        }
        let total = PayabliPayInSummaryRows.totalRowAmount(paymentDetails: paymentDetails)
        guard total != nil || !figures.isEmpty else { return inputs }

        let at = drawnSummaryIndex(in: sections)
        let summary = at.map { sections[$0] }
            ?? PayabliPayInFieldSection(fields: amountFields, style: .summary)
        let order = (summary.fields.filter(amountFields.contains) + amountFields).uniqued()
        let rows = order.compactMap { field in figures[field].map { PayInDrawnSection.Row(field: field, amount: $0) } }
        let drawn = PayInDrawnSection(section: summary.replacingFields(order), rows: rows, total: total)

        guard let at else { return inputs + [drawn] }
        // Where the host put it, among the inputs drawn before and after it.
        let before = sections[..<at].filter { section in
            section.style == .inputs && section.fields.contains { !amountFields.contains($0) }
        }.count
        return Array(inputs.prefix(before)) + [drawn] + Array(inputs.dropFirst(before))
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
