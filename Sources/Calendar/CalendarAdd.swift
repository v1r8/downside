import SwiftUI
import AppKit
import EventKit
import UniformTypeIdentifiers

struct ParsedICS {
    var title: String
    var start: Date
    var end: Date?
    var isAllDay: Bool
    var location: String?
    var notes: String?
}

/// Parser básico de .ics: primeiro VEVENT, campos essenciais.
enum ICSParser {
    static func parse(url: URL) -> ParsedICS? {
        guard let raw = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        else { return nil }

        // "Unfold": linhas continuadas começam com espaço/tab.
        let unfolded = raw
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")

        var fields: [String: (params: [String: String], value: String)] = [:]
        var inEvent = false
        for line in unfolded.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "BEGIN:VEVENT" { inEvent = true; continue }
            if trimmed == "END:VEVENT" { break }
            guard inEvent, let colon = trimmed.firstIndex(of: ":") else { continue }

            let head = String(trimmed[..<colon])
            let value = String(trimmed[trimmed.index(after: colon)...])
            let parts = head.split(separator: ";")
            guard let name = parts.first.map(String.init) else { continue }

            var params: [String: String] = [:]
            for part in parts.dropFirst() {
                let pair = part.split(separator: "=", maxSplits: 1)
                if pair.count == 2 {
                    params[String(pair[0])] = String(pair[1])
                }
            }
            if fields[name.uppercased()] == nil {
                fields[name.uppercased()] = (params, value)
            }
        }

        guard let startField = fields["DTSTART"],
              let (start, isAllDay) = date(from: startField)
        else { return nil }

        let end = fields["DTEND"].flatMap { date(from: $0)?.0 }
        let title = fields["SUMMARY"].map { unescape($0.value) }
            ?? url.deletingPathExtension().lastPathComponent

        return ParsedICS(
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: fields["LOCATION"].map { unescape($0.value) },
            notes: fields["DESCRIPTION"].map { unescape($0.value) }
        )
    }

    private static func date(
        from field: (params: [String: String], value: String)
    ) -> (Date, Bool)? {
        let value = field.value
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if value.count == 8, value.allSatisfy(\.isNumber) {
            formatter.dateFormat = "yyyyMMdd"
            formatter.timeZone = .current
            return formatter.date(from: value).map { ($0, true) }
        }
        if value.hasSuffix("Z") {
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter.date(from: value).map { ($0, false) }
        }
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = field.params["TZID"].flatMap(TimeZone.init(identifier:)) ?? .current
        return formatter.date(from: value).map { ($0, false) }
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

@MainActor
enum CalendarService {
    static let store = EKEventStore()

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter(\.allowsContentModifications)
    }

    static func add(_ ics: ParsedICS, to calendar: EKCalendar) throws {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = ics.title
        event.startDate = ics.start
        event.endDate = ics.end ?? ics.start.addingTimeInterval(ics.isAllDay ? 0 : 3600)
        event.isAllDay = ics.isAllDay
        event.location = ics.location
        event.notes = ics.notes
        try store.save(event, span: .thisEvent, commit: true)
    }
}

/// Pill azul com ícone de calendário+. Ao clicar, faz fade-in da lista
/// de calendários; escolher um adiciona o evento direto na Agenda.
struct CalendarAddButton: View {
    let url: URL
    let scale: CGFloat

    private enum Phase: Equatable {
        case idle
        case choosing([EKCalendar])
        case done
    }

    @State private var phase = Phase.idle

    var body: some View {
        Group {
            switch phase {
            case .idle:
                Button {
                    Task { await beginChoosing() }
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8 * scale)
                        .padding(.vertical, 3 * scale)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.borderless)
                .help("Adicionar evento à Agenda")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))

            case .choosing(let calendars):
                HStack(spacing: 4 * scale) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4 * scale) {
                            ForEach(calendars, id: \.calendarIdentifier) { calendar in
                                Button {
                                    add(to: calendar)
                                } label: {
                                    HStack(spacing: 4 * scale) {
                                        Circle()
                                            .fill(Color(nsColor: calendar.color ?? .systemBlue))
                                            .frame(width: 6 * scale, height: 6 * scale)
                                        Text(calendar.title)
                                            .font(.system(size: 10 * scale))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 7 * scale)
                                    .padding(.vertical, 3 * scale)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .frame(maxWidth: 220 * scale)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { phase = .idle }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10 * scale))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .done:
                HStack(spacing: 3 * scale) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9 * scale, weight: .bold))
                    Text("Adicionado")
                        .font(.system(size: 10 * scale, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 3 * scale)
                .background(Capsule().fill(Color.green))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: phase)
    }

    private func beginChoosing() async {
        guard ICSParser.parse(url: url) != nil, await CalendarService.requestAccess() else {
            // Sem parse ou sem permissão: deixa o app Agenda resolver.
            NSWorkspace.shared.open(url)
            return
        }
        let calendars = CalendarService.writableCalendars()
        guard !calendars.isEmpty else {
            NSWorkspace.shared.open(url)
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) {
            phase = .choosing(calendars)
        }
    }

    private func add(to calendar: EKCalendar) {
        guard let ics = ICSParser.parse(url: url) else {
            NSWorkspace.shared.open(url)
            return
        }
        do {
            try CalendarService.add(ics, to: calendar)
            withAnimation(.easeInOut(duration: 0.18)) { phase = .done }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.easeInOut(duration: 0.18)) { phase = .idle }
            }
        } catch {
            NSWorkspace.shared.open(url)
            withAnimation(.easeInOut(duration: 0.18)) { phase = .idle }
        }
    }
}
