import Foundation

public struct Configuration: Codable, Sendable {
    public let voiceover: [Workflow]
    public init(voiceover: [Workflow]) { self.voiceover = voiceover }

    /// Deliberately small YAML subset: one list, id/task/goal scalars, folded goals.
    /// No aliases, tags, environment interpolation, or silently ignored keys.
    public static func parse(_ text: String) throws -> Configuration {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            let value = try JSONDecoder().decode(Configuration.self, from: Data(text.utf8))
            try value.validate(); return value
        }
        var rows: [[String: String]] = []
        var rootSeen = false
        var folding = false
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") { continue }
            guard !raw.contains("\t") else { throw GateError.invalid("Tabs are unsupported at line \(index+1)") }
            let indent = raw.prefix(while: { $0 == " " }).count
            if folding && indent >= 6 {
                rows[rows.count-1]["goal", default: ""] += (rows.last?["goal"] == "" ? "" : " ") + s
                continue
            }
            folding = false
            if s == "voiceover:" && indent == 0 && !rootSeen { rootSeen = true; continue }
            guard rootSeen else { throw GateError.invalid("Expected voiceover: at line \(index+1)") }
            var line = s
            if indent == 2 && s.hasPrefix("- ") { rows.append([:]); line = String(s.dropFirst(2)) }
            else if indent != 4 { throw GateError.invalid("Unsupported YAML structure at line \(index+1)") }
            guard !rows.isEmpty, let colon = line.firstIndex(of: ":") else { throw GateError.invalid("Expected key: value at line \(index+1)") }
            let key = String(line[..<colon])
            var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard ["id", "task", "goal"].contains(key), rows[rows.count-1][key] == nil else {
                throw GateError.invalid("Unknown or duplicate key '\(key)' at line \(index+1)")
            }
            if key == "goal" && value == ">" { folding = true; value = "" }
            else if value.hasPrefix("\"") {
                value = try JSONDecoder().decode(String.self, from: Data(value.utf8))
            } else if value.contains("#") || value.hasPrefix("&") || value.hasPrefix("*") || value.hasPrefix("!") || value.hasPrefix("'") {
                throw GateError.invalid("Use double quotes for this scalar at line \(index+1)")
            }
            rows[rows.count-1][key] = value
        }
        let workflows = try rows.map { row -> Workflow in
            guard let id = row["id"], let task = row["task"], let goal = row["goal"] else {
                throw GateError.invalid("Each workflow requires id, task, and goal")
            }
            return Workflow(id: id, task: task, goal: goal)
        }
        let value = Configuration(voiceover: workflows)
        try value.validate(); return value
    }
    public func validate() throws {
        guard !voiceover.isEmpty, voiceover.count <= 20 else { throw GateError.invalid("Declare 1–20 workflows") }
        guard Set(voiceover.map(\.id)).count == voiceover.count else { throw GateError.invalid("Duplicate workflow IDs") }
        for w in voiceover {
            guard !w.id.isEmpty, !w.task.isEmpty, !w.goal.isEmpty,
                  w.id.count <= 80, w.task.count <= 100, w.goal.count <= 2000 else {
                throw GateError.invalid("Invalid workflow lengths")
            }
        }
    }
}
