import SwiftUI

struct ProjectCurrencyPicker: View {
    let selection: String
    let onSelect: (String) -> Void
    @State private var search = ""
    private var currencies: [String] {
        ProjectHourlyRate.currencies.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) || title($0).localizedCaseInsensitiveContains(search) }
    }
    private func title(_ code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Currency").font(KeepTheme.headingFont(size: 22))
            TextField("Search currencies", text: $search).textFieldStyle(.roundedBorder)
                .onSubmit { if let code = currencies.first { onSelect(code) } }
            KeepOptionList(label: "Currencies", options: currencies, selection: selection,
                           title: { "\($0) · \(title($0))" }, onSelect: onSelect)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }.padding(16).frame(width: 330, height: 390)
            .foregroundStyle(KeepTheme.ink).background(KeepTheme.paper)
    }
}
