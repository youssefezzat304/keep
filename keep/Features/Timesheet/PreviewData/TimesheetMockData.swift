import SwiftUI

/// Display fixtures only. There is no session history or timer dependency.
struct TimesheetDayPreview: Identifiable {
    let id: String
    let date: String
    var isWeekend = false
}

struct TimesheetProjectPreview: Identifiable {
    let id: String
    let name: String
    let category: String
    let color: Color
    let hours: [String]
    let total: String
}

enum TimesheetMockData {
    static let weekRange = "28 Sep – 4 Oct, 2026"
    static let weekNumber = "W40"
    static let weekTotal = "26h 30m"
    static let projectCount = "4 projects"

    static let days = [
        TimesheetDayPreview(id: "MON", date: "28"),
        TimesheetDayPreview(id: "TUE", date: "29"),
        TimesheetDayPreview(id: "WED", date: "30"),
        TimesheetDayPreview(id: "THU", date: "01"),
        TimesheetDayPreview(id: "FRI", date: "02"),
        TimesheetDayPreview(id: "SAT", date: "03", isWeekend: true),
        TimesheetDayPreview(id: "SUN", date: "04", isWeekend: true)
    ]

    static let projects = [
        TimesheetProjectPreview(
            id: "keep", name: "Keep", category: "Personal project", color: KeepTheme.accent,
            hours: ["2:15", "1:30", "3:00", "2:45", "1:15", "—", "—"], total: "10h 45m"
        ),
        TimesheetProjectPreview(
            id: "german", name: "Learning German", category: "Language learning", color: KeepTheme.sage,
            hours: ["0:45", "1:00", "0:30", "1:15", "0:45", "0:30", "—"], total: "4h 45m"
        ),
        TimesheetProjectPreview(
            id: "website", name: "Website refresh", category: "Design & development", color: KeepTheme.mistBlue,
            hours: ["1:30", "—", "2:00", "1:00", "2:30", "—", "—"], total: "7h 00m"
        ),
        TimesheetProjectPreview(
            id: "reading", name: "Reading & research", category: "A little curiosity", color: KeepTheme.highlight,
            hours: ["0:30", "0:45", "—", "0:30", "0:45", "1:00", "0:30"], total: "4h 00m"
        )
    ]

    static let dailyTotals = ["5:00", "3:15", "5:30", "5:30", "5:15", "1:30", "0:30"]
}
