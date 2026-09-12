import Foundation

public enum ReportRenderer {
    public static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    public static func markdown(_ report: RunReport) -> String {
        // HTML escaping also prevents arbitrary UI strings becoming raw HTML in a GitHub summary.
        func cell(_ value: String) -> String {
            var safe = escape(value).replacingOccurrences(of: "|", with: "&#124;").replacingOccurrences(of: "\n", with: " ")
            for (character, entity) in [("[", "&#91;"), ("]", "&#93;"), ("`", "&#96;"), ("*", "&#42;"), ("_", "&#95;")] {
                safe = safe.replacingOccurrences(of: character, with: entity)
            }
            return safe
        }
        var lines = ["# A11yGate", "", "Execution mode: **\(report.mode.rawValue)**", "", "VoiceOver readiness: **\(cell(report.voiceOverReadiness))**", "",
                     "| Workflow | Result | Completed / attempted actions |", "|---|---|---|"]
        for result in report.results {
            lines.append("| \(cell(result.workflow.task)) | \(result.status.rawValue.uppercased()) | \(result.steps.filter(\.completed).count) / \(result.steps.count) |")
        }
        lines += ["", "Device: \(cell(report.device)). Generated: \(cell(report.generatedAt)).", "",
                  "VoiceOver mode covers experimental sequential navigation with XCTest-injected text. It does not test the VoiceOver keyboard or certify an app-wide claim."]
        for result in report.results {
            lines += ["", "## \(cell(result.workflow.task))", "", cell(result.diagnosis.reason), "", "Evidence certainty: \(cell(result.diagnosis.certainty))"]
            if let suggestion = result.diagnosis.suggestion { lines += ["", "Suggested remediation: \(cell(suggestion))"] }
        }
        if let error = report.infrastructureError { lines += ["", "Infrastructure error: \(cell(error))"] }
        return lines.joined(separator: "\n") + "\n"
    }
    public static func html(_ report: RunReport) -> String {
        let e = escape
        func state(_ observation: Observation) -> String {
            let elements = observation.elements.map { "<tr><td>\(e($0.id))</td><td>\(e($0.label))</td><td>\(e($0.role))</td></tr>" }.joined()
            return """
            <dl><dt>Screen</dt><dd>\(e(observation.screen))</dd><dt>Speech</dt><dd>\(e(observation.voiceOverOutput ?? "Unavailable"))</dd>
            <dt>Speech source</dt><dd>\(e(observation.speechSource))</dd><dt>Inferred focus</dt><dd>\(e(observation.focusedElement ?? "Unknown"))</dd>
            <dt>Focus source</dt><dd>\(e(observation.focusSource ?? "Unavailable"))</dd></dl>
            <details><summary>Observed elements (\(observation.elements.count))</summary><div class="table-scroll"><table><caption>UI snapshot</caption><thead><tr><th scope="col">Identifier</th><th scope="col">Label</th><th scope="col">Role</th></tr></thead><tbody>\(elements)</tbody></table></div></details>
            """
        }
        let rows = report.results.enumerated().map { index, result in
            "<tr><th scope=\"row\"><a href=\"#workflow-\(index)\">\(e(result.workflow.task))</a></th><td>\(result.status.rawValue.uppercased())</td><td>\(result.steps.filter(\.completed).count) / \(result.steps.count)</td></tr>"
        }.joined()
        let sections = report.results.enumerated().map { index, result in
            let steps = result.steps.map { step in
                """
                <details id="workflow-\(index)-\(step.evidenceID)"><summary>\(step.evidenceID) · \(step.action.kind.rawValue) · \(e(step.action.target ?? "current focus")) · \(step.completed ? "completed" : "error")</summary>
                <p>\(e(step.startedAt ?? "Time unavailable")) → \(e(step.completedAt ?? "Time unavailable"))</p>
                \(step.error.map { "<p class=\"notice\">Action error: \(e($0))</p>" } ?? "")
                <h4>Before</h4>\(state(step.before))
                <h4>After</h4>\(step.afterObserved == false ? "<p>Not observed. The stored state is the last known state.</p>" : state(step.after))
                </details>
                """
            }.joined()
            let caps = result.capabilities.map { "<p>Capability probe: \($0.usable ? "passed for this run" : "not established"). VoiceOver state restored: \($0.restored ? "yes" : "no"). \(e($0.error ?? ""))</p>" } ?? ""
            return """
            <section id="workflow-\(index)"><h2>\(e(result.workflow.task)) <span class="status">\(result.status.rawValue.uppercased())</span></h2>
            <p>\(e(result.workflow.goal))</p><h3>Finding</h3><p>\(e(result.diagnosis.reason))</p>
            <p>Certainty: \(e(result.diagnosis.certainty))</p>
            \(result.diagnosis.suggestion.map { "<h3>Suggested remediation</h3><p>\(e($0))</p>" } ?? "")
            \(caps)<h3>Action timeline</h3>\(steps.isEmpty ? "<p>No actions executed.</p>" : steps)
            \(result.lastObservation.map { "<h3>Last observation</h3>" + state($0) } ?? "")</section>
            """
        }.joined()
        return """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <title>A11yGate — Workflow evidence</title><style>
        :root{color-scheme:light dark}*{box-sizing:border-box}body{margin:0;background:#10191e;color:#edf3f5;font:17px/1.6 system-ui,sans-serif}main{max-width:1050px;margin:auto;padding:36px 22px}a{color:#78dfd3}a:focus-visible,summary:focus-visible{outline:3px solid #ffd172;outline-offset:5px}h1{font-size:clamp(2.3rem,6vw,4rem);line-height:1.1;margin-bottom:8px}h2{font-size:1.65rem}h3{margin-bottom:6px}.eyebrow{letter-spacing:.12em;text-transform:uppercase;color:#a9bfc8}.notice{padding:16px;border-left:4px solid #ffd172;background:#253138}.status{font:700 .85rem system-ui;border:1px solid #829ba7;padding:5px 9px;border-radius:5px;white-space:nowrap}section{margin-top:42px;padding-top:22px;border-top:1px solid #536670}table{border-collapse:collapse;width:100%}th,td{padding:12px;text-align:left;border-bottom:1px solid #536670;overflow-wrap:anywhere}caption{text-align:left;font-weight:600;padding:10px}details{margin:12px 0;padding:14px;background:#1a282f;border:1px solid #536670;border-radius:6px}summary{cursor:pointer;font-weight:600;overflow-wrap:anywhere}dt{font-weight:700;color:#b7cbd4}dd{margin:0 0 10px;overflow-wrap:anywhere}.table-scroll{overflow:auto}.skip{position:absolute;left:-10000px}.skip:focus{left:12px;top:8px;background:#10191e;padding:8px}footer{margin-top:36px;color:#b7cbd4}@media(prefers-reduced-motion:reduce){*{scroll-behavior:auto}}@media print{body{background:white;color:black}a{color:black}details{background:white}main{max-width:none}}
        </style></head><body><a class="skip" href="#results">Skip to results</a><main>
        <p class="eyebrow">Workflow evidence · \(e(report.mode.rawValue)) · \(e(report.fixture)) fixture</p><h1>A11yGate</h1><p>Don’t claim accessibility. Prove it.</p>
        <p class="notice"><strong>VoiceOver readiness: \(e(report.voiceOverReadiness))</strong><br>Experimental sequential VoiceOver navigation uses XCTest-injected text. Keyboard accessibility and app-wide accessibility are not established by this report.</p>
        <p>\(e(report.device)) · \(e(report.xcode)) · \(e(report.generatedAt))</p>
        \(report.infrastructureError.map { "<p class=\"notice\">Infrastructure error: \(e($0))</p>" } ?? "")
        <div id="results" class="table-scroll"><table><caption>Declared workflow results</caption><thead><tr><th scope="col">Workflow</th><th scope="col">Result</th><th scope="col">Completed / attempted actions</th></tr></thead><tbody>\(rows)</tbody></table></div>
        \(sections)<footer>Local engineering evidence. No legal certification. UI content is escaped; this report loads no scripts, fonts, analytics, or external resources.</footer></main></body></html>
        """
    }
}

public enum ReportComparison {
    public static func text(before: RunReport, after: RunReport) throws -> String {
        guard before.mode == after.mode, before.device == after.device,
              before.results.map(\.workflow) == after.results.map(\.workflow) else {
            throw GateError.invalid("Compare requires the same mode, device/OS, and declared workflows")
        }
        var lines = ["A11yGate — Before / After (\(before.mode.rawValue))", ""]
        for (old, new) in zip(before.results, after.results) {
            lines.append("\(old.workflow.task): \(old.status.rawValue.uppercased()) → \(new.status.rawValue.uppercased())")
        }
        lines += ["", "This comparison does not add coverage or convert a functional run into VoiceOver evidence."]
        if before.infrastructureError != nil || after.infrastructureError != nil { lines.append("At least one run has an infrastructure error; no clean regression verdict.") }
        return lines.joined(separator: "\n")
    }
}
