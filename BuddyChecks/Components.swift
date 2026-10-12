import SwiftUI
import BuddyCheckCore

enum Palette {
    static let navy = Color(red: 16 / 255, green: 43 / 255, blue: 70 / 255)
    static let canvas = Color(red: 233 / 255, green: 239 / 255, blue: 242 / 255)
    static let surface = Color.white
    static let action = navy
    static let actionSurface = Color(red: 229 / 255, green: 237 / 255, blue: 243 / 255)
    static let actionInk = navy
    static let context = Color(red: 220 / 255, green: 231 / 255, blue: 238 / 255)
    static let border = Color(red: 190 / 255, green: 206 / 255, blue: 216 / 255)
    static let paper = Color(red: 241 / 255, green: 231 / 255, blue: 208 / 255)
    static let gold = Color(red: 182 / 255, green: 138 / 255, blue: 61 / 255)
    static let ink = Color(red: 23 / 255, green: 45 / 255, blue: 66 / 255)
    static let success = Color(red: 220 / 255, green: 236 / 255, blue: 227 / 255)
    static let green = Color(red: 40 / 255, green: 115 / 255, blue: 91 / 255)
    static let red = Color(red: 140 / 255, green: 22 / 255, blue: 34 / 255)
}

struct ActionStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .foregroundStyle(primary ? Palette.surface : Palette.navy)
            .background(primary ? Palette.navy : Palette.surface, in: Capsule())
            .overlay(Capsule().stroke(Palette.navy.opacity(primary ? 1 : 0.65), lineWidth: 1))
            .opacity(!enabled ? 0.38 : (configuration.isPressed ? 0.75 : 1))
    }
}
struct RowActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Palette.ink).padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Palette.context : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.border.opacity(0.55)).frame(height: 0.5) }
    }
}
struct ChoiceStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 10).foregroundStyle(Palette.ink)
            .background(selected ? Palette.actionSurface : Palette.surface)
            .overlay(alignment: .leading) { if selected { Rectangle().fill(Palette.navy).frame(width: 3) } }
            .overlay(alignment: .bottom) { Divider() }
            .contentShape(Rectangle()).opacity(configuration.isPressed ? 0.65 : 1)
    }
}
struct Page<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var scrollResetID: String? = nil
    var spacing: CGFloat = 24
    var topPadding: CGFloat = 24
    var decorated = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: spacing, content: content)
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, textSize.isAccessibilitySize ? 16 : 24)
                    .padding(.top, topPadding).padding(.bottom, 32).frame(maxWidth: .infinity)
                    .tint(Palette.action).environment(\.colorScheme, .light)
                    .id("page-top")
            }
            .modifier(PageScrollEdge())
            .onChange(of: scrollResetID) { _, _ in reader.scrollTo("page-top", anchor: .top) }
        }
        .background {
            Palette.canvas
            if decorated {
                GeometryReader { proxy in
                    Circle().stroke(Palette.border.opacity(0.23), lineWidth: 26)
                        .overlay(Circle().stroke(Palette.border.opacity(0.4), lineWidth: 1))
                        .frame(width: 350, height: 350)
                        .position(x: proxy.size.width - 20, y: proxy.size.height - 120)
                }.clipped().allowsHitTesting(false)
            }
        }.foregroundStyle(Palette.ink).tint(Palette.navy)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Palette.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}
private struct PageScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectStyle(.hard, for: .bottom) }
        else { content }
    }
}
struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View { Text(title).font(.title2.bold()).foregroundStyle(Palette.navy).accessibilityAddTraits(.isHeader) }
}
struct SectionBand<Content: View>: View {
    var color: Color = Palette.surface
    var spacing: CGFloat = 16
    var verticalPadding: CGFloat = 22
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, verticalPadding)
            .background(color)
            .overlay(alignment: .bottom) { Divider().overlay(Palette.border.opacity(0.5)) }
            .padding(.horizontal, -24)
    }
}
struct WorkingSurface<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { SectionBand(content: content) }
}
struct PersonAvatar: View {
    let name: String
    var size: CGFloat = 52
    var gold = false
    private var initials: String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }
    var body: some View {
        Text(initials).font(size > 64 ? .largeTitle.weight(.semibold) : .headline)
            .foregroundStyle(gold ? Palette.navy : Palette.ink)
            .frame(width: size, height: size)
            .background(gold ? Palette.paper : Palette.context, in: Circle())
            .overlay(Circle().stroke(gold ? Palette.gold : Palette.border, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
struct PersonCard: View {
    let name: String
    init(person: Person) { name = person.name }
    init(name: String) { self.name = name }
    var body: some View {
        HStack(spacing: 13) {
            PersonAvatar(name: name, size: 42)
            Text(name).font(.title3.bold()).accessibilityAddTraits(.isHeader)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct MemberProfile: View {
    let name: String
    var subtitle: String = ""
    var body: some View {
        VStack(spacing: 12) {
            PersonAvatar(name: name, size: 86, gold: true)
            Text(name).font(.title.bold())
            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.8)) }
        }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
            .foregroundStyle(.white).background { Palette.navy.overlay { BrandRings().clipped() } }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.gold).frame(height: 3) }
            .padding(.horizontal, -24)
    }
}
struct BrandRings: View {
    var body: some View {
        GeometryReader { proxy in
            Circle().stroke(.white.opacity(0.06), lineWidth: 25)
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
                .frame(width: 250, height: 250).position(x: proxy.size.width, y: proxy.size.height)
        }.allowsHitTesting(false)
    }
}
struct BuddyMasthead: View {
    let post: String
    let openSettings: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            ZStack { Image("BuddyGold").resizable(); Image("BuddyIvory").resizable() }
                .frame(width: 74, height: 74).padding(.horizontal, -8)
            VStack(alignment: .leading, spacing: 6) {
                Text("Buddy Checks").font(.largeTitle.bold()).tracking(-0.9).lineLimit(1).minimumScaleFactor(0.85)
                Label(post, systemImage: "star").font(.footnote).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            Button(action: openSettings) { Image(systemName: "person.crop.circle").font(.system(size: 32, weight: .ultraLight)) }
                .accessibilityLabel("Account and Post settings")
        }.foregroundStyle(.white).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 14)
            .background { Palette.navy.overlay { BrandRings().clipped() }.ignoresSafeArea(edges: .top) }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.gold).frame(height: 3) }
            .padding(.horizontal, -24)
    }
}
struct PageInvitation: View {
    let title: String
    let detail: String
    var symbol = "person"
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title2.bold())
                Text(detail).font(.body).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: symbol).font(.title3).foregroundStyle(Palette.navy)
                .frame(width: 49, height: 49).background(.white, in: Circle())
        }
    }
}
struct ConversationPrompt: View {
    let firstName: String
    var body: some View {
        SectionBand(color: Palette.paper, spacing: 10) {
            Label("A way to start", systemImage: "quote.opening").font(.title3.bold())
            Text("“Hi \(firstName), I'm checking in from the Post. How have you been?”")
                .font(.body).lineSpacing(4).padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(Palette.gold).frame(width: 3) }
        }
    }
}
struct ConfirmationHeading: View {
    let title: String
    let name: String
    var body: some View {
        SectionBand(color: Palette.success, spacing: 14) {
            Image(systemName: "checkmark").font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Palette.green).frame(width: 70, height: 70)
                .background(.white.opacity(0.8), in: Circle())
                .overlay(Circle().stroke(Palette.green.opacity(0.5), lineWidth: 2))
                .frame(maxWidth: .infinity)
            Text(title).font(.title.bold()).frame(maxWidth: .infinity)
            Text(name).foregroundStyle(Palette.green).frame(maxWidth: .infinity)
        }
    }
}
struct ReceiptRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
        }.font(.body).padding(.vertical, 10).overlay(alignment: .bottom) { Divider() }
    }
}
struct CalendarStamp: View {
    let date: Date
    var zone: String = TimeZone.current.identifier
    private func part(_ template: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: zone) ?? .current
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
    var body: some View {
        VStack(spacing: 0) {
            Text(part("MMM")).font(.caption2)
            Text(part("d")).font(.title.weight(.semibold))
        }.frame(width: 48).padding(.vertical, 5).background(Palette.paper)
            .overlay(alignment: .top) { Rectangle().fill(Palette.gold).frame(height: 3) }
    }
}
struct ActionRow: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary).accessibilityHidden(true)
        }.frame(minHeight: 32)
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
