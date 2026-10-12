import SwiftUI
import BuddyCheckCore

enum Palette {
    static let navy = Color(red: 10 / 255, green: 34 / 255, blue: 64 / 255)
    static let canvas = Color(red: 240 / 255, green: 242 / 255, blue: 245 / 255)
    static let surface = Color.white
    static let action = Color(red: 20 / 255, green: 102 / 255, blue: 204 / 255)
    static let actionSurface = Color(red: 227 / 255, green: 238 / 255, blue: 255 / 255)
    static let actionInk = Color(red: 16 / 255, green: 79 / 255, blue: 156 / 255)
    static let border = Color(red: 123 / 255, green: 135 / 255, blue: 152 / 255)
    static let paper = Color(red: 251 / 255, green: 247 / 255, blue: 236 / 255)
    static let gold = Color(red: 198 / 255, green: 161 / 255, blue: 91 / 255)
    static let ink = Color(red: 27 / 255, green: 34 / 255, blue: 43 / 255)
    static let red = Color(red: 140 / 255, green: 22 / 255, blue: 34 / 255)
}

struct ActionStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .foregroundStyle(primary ? Palette.surface : Palette.actionInk)
            .background(primary ? Palette.action : Palette.actionSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.action, lineWidth: 1.25))
            .opacity(!enabled ? 0.5 : (configuration.isPressed ? 0.75 : 1))
    }
}
struct RowActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Palette.actionInk).padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.actionSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.action, lineWidth: 1.25))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
struct Page<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var scrollResetID: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 24, content: content)
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, textSize.isAccessibilitySize ? 16 : 24)
                    .padding(.top, 24).padding(.bottom, 32).frame(maxWidth: .infinity)
                    .tint(Palette.action).environment(\.colorScheme, .light)
                    .id("page-top")
            }
            .modifier(PageScrollEdge())
            .onChange(of: scrollResetID) { _, _ in reader.scrollTo("page-top", anchor: .top) }
        }
        .background(Palette.canvas).foregroundStyle(Palette.ink).tint(Palette.surface)
        .toolbarBackground(Palette.navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PageScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            content
        }
    }
}

struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.title2.bold()).foregroundStyle(Palette.navy).accessibilityAddTraits(.isHeader) }
}
struct PersonCard: View {
    let name: String
    init(person: Person) { name = person.name }
    init(name: String) { self.name = name }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(Palette.gold).frame(width: 44, height: 4).accessibilityHidden(true)
            Text(name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .foregroundStyle(Palette.surface)
            .background(Palette.navy, in: RoundedRectangle(cornerRadius: 16))
    }
}
struct WorkingSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}
struct ActionRow: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title3.bold())
                if let subtitle { Text(subtitle).font(.subheadline) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").accessibilityHidden(true)
        }.frame(minHeight: 24)
    }
}
func dateText(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) }
func timeZoneText(_ identifier: String = TimeZone.current.identifier) -> String {
    (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ") + " time"
}

struct DateTimeFields: View {
    @Binding var selection: Date
    var future: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date").font(.headline)
            picker("Date", components: .date)
            Text("Time").font(.headline)
            picker("Time", components: .hourAndMinute)
        }
    }
    @ViewBuilder private func picker(_ title: String, components: DatePickerComponents) -> some View {
        Group {
            if future { DatePicker(title, selection: $selection, in: Date()..., displayedComponents: components) }
            else { DatePicker(title, selection: $selection, in: ...Date(), displayedComponents: components) }
        }.datePickerStyle(.compact).labelsHidden()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityValue(selection.formatted(date: components == .date ? .abbreviated : .omitted, time: components == .date ? .omitted : .shortened))
            .accessibilityAddTraits(.isButton)
    }
}
