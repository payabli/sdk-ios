import SwiftUI

/// Expiration month/year picker (PRD FR-1.6).
///
/// On iOS presents a bottom sheet with two SwiftUI `Picker` wheels
/// (month + year). On macOS (used only for local `swift test`) falls back to a
/// `Menu`-style dropdown.
///
/// Tapping the summary row opens the sheet. The sheet is dismissed by tapping
/// "Done" or swiping down — matching the native iOS form pattern.
@available(iOS 15.0, macOS 12.0, *)
struct ExpirationPickerView: View {
    @Binding var month: Int
    @Binding var year: Int
    let cornerRadius: CGFloat

    @State private var showingSheet = false

    private static let years: [Int] = {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 20))
    }()

    var body: some View {
        Button(action: { showingSheet = true }) {
            HStack {
                Text("\(String(format: "%02d", month)) / \(String(format: "%04d", year))")
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .sheet(isPresented: $showingSheet) {
            if #available(iOS 16.0, *) {
                WheelSheet(month: $month, year: $year, isPresented: $showingSheet)
                    .presentationDetents([.height(320), .medium])
            } else {
                WheelSheet(month: $month, year: $year, isPresented: $showingSheet)
            }
        }
        #else
        .sheet(isPresented: $showingSheet) {
            WheelSheet(month: $month, year: $year, isPresented: $showingSheet)
                .frame(width: 320, height: 320)
        }
        #endif
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct WheelSheet: View {
    @Binding var month: Int
    @Binding var year: Int
    @Binding var isPresented: Bool

    private static let years: [Int] = {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear...(currentYear + 20))
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Expiration date").font(.headline)
                Spacer()
                Button("Done") { isPresented = false }
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                Picker("Month", selection: $month) {
                    ForEach(1...12, id: \.self) { m in
                        Text("\(String(format: "%02d", m)) — \(monthName(m))").tag(m)
                    }
                }
                #if os(iOS)
                .pickerStyle(.wheel)
                #endif
                .clipped()
                .frame(maxWidth: .infinity)

                Picker("Year", selection: $year) {
                    ForEach(Self.years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                #if os(iOS)
                .pickerStyle(.wheel)
                #endif
                .clipped()
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)

            Spacer()
        }
    }

    private func monthName(_ m: Int) -> String {
        DateFormatter().monthSymbols[safe: m - 1] ?? ""
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
