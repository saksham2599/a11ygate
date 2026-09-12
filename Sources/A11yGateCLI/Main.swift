import Foundation
import Darwin
import A11yGateCore
import A11yGateAgent

@main struct A11yGateCLI {
    @MainActor static func main() async {
        do { exit(try await run(Array(CommandLine.arguments.dropFirst()))) }
        catch { fputs("A11yGate: \(error.localizedDescription)\n", stderr); exit(2) }
    }
    @MainActor static func run(_ args: [String]) async throws -> Int32 {
        guard let command = args.first, command != "--help", command != "help" else { print(help); return 0 }
        let options = try Options(Array(args.dropFirst()))
        if command == "report" {
            let data = try Data(contentsOf: URL(fileURLWithPath: try options.required("--input")))
            let report = try JSONDecoder().decode(RunReport.self, from: data)
            let format = options.values["--format"] ?? "terminal"
            let rendered: String
            switch format {
            case "terminal": rendered = report.terminal()
            case "html": rendered = ReportRenderer.html(report)
            case "markdown": rendered = ReportRenderer.markdown(report)
            default: throw GateError.invalid("Report format must be terminal, html, or markdown")
            }
            if let path = options.values["--output"] { try rendered.write(toFile: path, atomically: true, encoding: .utf8); print("Saved \(path)") }
            else { print(rendered) }
            return report.exitCode
        }
        if command == "compare" {
            let before = try JSONDecoder().decode(RunReport.self, from: Data(contentsOf: URL(fileURLWithPath: try options.required("--before"))))
            let after = try JSONDecoder().decode(RunReport.self, from: Data(contentsOf: URL(fileURLWithPath: try options.required("--after"))))
            let summary = try ReportComparison.text(before: before, after: after)
            if let path = options.values["--output"] { try summary.write(toFile: path, atomically: true, encoding: .utf8) }
            print(summary); return after.exitCode
        }
        if command == "diagnose" {
            guard options.flags.contains("--allow-cloud") else {
                throw GateError.invalid("Cloud diagnosis sends report text to OpenAI. Review it, then use --allow-cloud explicitly.")
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: try options.required("--input")))
            let report = try JSONDecoder().decode(RunReport.self, from: data)
            let env = ProcessInfo.processInfo.environment
            let metrics = APICallRecorder()
            let transport = try OpenAITransport(key: env["OPENAI_API_KEY"] ?? "", model: env["A11YGATE_MODEL"] ?? "gpt-6-astra", recorder: metrics)
            var source: SourceExcerpt?
            if let path = options.values["--source"] {
                let text = try String(contentsOfFile: path, encoding: .utf8)
                guard text.utf8.count <= 32_768 else { throw GateError.invalid("Source excerpt exceeds 32 KiB; provide a narrow file") }
                source = SourceExcerpt(path: URL(fileURLWithPath: path).lastPathComponent, text: text)
            }
            let diagnosis = try await DiagnosisService.diagnose(report, transport: transport, source: source)
            let output = URL(fileURLWithPath: options.values["--output"] ?? "diagnosis.json")
            try writeJSON(diagnosis, to: output)
            try writeJSON(await metrics.snapshot(), to: output.appendingPathExtension("usage.json"))
            print("Hypothesis: \(diagnosis.reason)\nSuggestion: \(diagnosis.suggestion ?? "none")\nSaved \(output.path)")
            return 0
        }
        let root = URL(fileURLWithPath: options.values["--root"] ?? FileManager.default.currentDirectoryPath).standardizedFileURL
        if command == "doctor" {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("a11ygate-doctor-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            print(try capture(["xcodebuild", "-version"], root: root, log: temp.appendingPathComponent("xcode.log")))
            print(try capture(["xcrun", "devicectl", "list", "devices"], root: root, log: temp.appendingPathComponent("devices.log")))
            print("VoiceOver service: requires Xcode 27 / iOS 27. Focus activation and text entry remain capability-gated.")
            print("Device execution: physical only. Cloud reasoning: opt-in. Screenshots: not retained by default.")
            return 0
        }
        guard ["test", "probe"].contains(command) else { throw GateError.invalid("Unknown command \(command). Use --help.") }
        let config = try Configuration.parse(String(contentsOf: root.appendingPathComponent(options.values["--config"] ?? "accessibility.yml"), encoding: .utf8))
        for w in config.voiceover { _ = try DemoContract.successID(w.id) }
        guard let mode = RunMode(rawValue: options.values["--mode"] ?? "voiceover") else { throw GateError.invalid("Mode must be voiceover or functional") }
        let device = try options.required("--device")
        let team = options.values["--team"] ?? ProcessInfo.processInfo.environment["A11YGATE_TEAM"] ?? ""
        guard !team.isEmpty else { throw GateError.invalid("Provide --team YOUR_TEAM_ID or A11YGATE_TEAM for local device signing") }
        let planner = options.values["--planner"] ?? "deterministic"
        guard ["deterministic", "astra"].contains(planner) else { throw GateError.invalid("Planner must be deterministic or astra") }
        if planner == "astra" {
            guard mode == .voiceover, options.flags.contains("--allow-cloud"), options.values["--agent-host"] != nil else {
                throw GateError.invalid("Astra planning requires VoiceOver mode, --allow-cloud, and --agent-host MAC_PRIVATE_IPV4. It sends synthetic observations to OpenAI.")
            }
        }
        let request = RunRequest(workflows: config.voiceover, mode: mode, fixed: options.flags.contains("--fixed"), screenshots: options.flags.contains("--screenshots"),
                                 experimentalVoiceOver: options.flags.contains("--experimental-voiceover"), planner: planner)
        let output = URL(fileURLWithPath: options.values["--output"] ?? root.appendingPathComponent("artifacts/\(UUID().uuidString)").path).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else { throw GateError.invalid("Output already exists; choose a new run directory") }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let xcode = (try? capture(["xcodebuild", "-version"], root: root, log: output.appendingPathComponent("xcode.log"))) ?? "unknown"
        var results: [WorkflowResult] = []
        var infrastructure: String?
        var deviceDescription = "Physical iPhone (details unavailable)"
        do {
            let infoURL = output.appendingPathComponent("device-details.json")
            defer { try? FileManager.default.removeItem(at: infoURL) } // Raw device metadata is not report evidence.
            _ = try capture(["xcrun", "devicectl", "device", "info", "details", "--device", device, "--json-output", infoURL.path], root: root, log: output.appendingPathComponent("device.log"))
            let info = try JSONSerialization.jsonObject(with: Data(contentsOf: infoURL)) as? [String: Any]
            let result = info?["result"] as? [String: Any]
            let hardware = result?["hardwareProperties"] as? [String: Any]
            let properties = result?["deviceProperties"] as? [String: Any]
            guard hardware?["reality"] as? String == "physical", hardware?["deviceType"] as? String == "iPhone" else {
                throw GateError.invalid("A physical iPhone is required. Simulator destinations are rejected.")
            }
            deviceDescription = "\(hardware?["marketingName"] as? String ?? "iPhone") / iOS \(properties?["osVersionNumber"] as? String ?? "unknown")"
            guard let xcodeDevice = hardware?["udid"] as? String else { throw GateError.invalid("Device UDID unavailable") }
            try? FileManager.default.removeItem(at: output.appendingPathComponent("device.log"))
            if command == "test" && mode == .voiceover {
                let os = properties?["osVersionNumber"] as? String ?? "unknown"
                let major = Int(os.split(separator: ".").first.map(String.init) ?? "") ?? 0
                if major < 27 || request.experimentalVoiceOver != true {
                let reason = major < 27
                    ? "Preflight only; workflows were not executed. This iPhone runs iOS \(os); XCUIVoiceOverService requires iOS 27 and Xcode 27."
                    : "Preflight only; workflows were not executed. Use --experimental-voiceover to run the compiled iOS 27 driver. Each run must pass navigation, focus activation, and injected-text capability checks before workflows execute."
                results = request.workflows.map { WorkflowResult(workflow: $0, mode: .voiceover, status: .unsupported, diagnosis: Diagnosis(reason: reason)) }
                let report = RunReport(mode: mode, fixed: request.fixed, device: deviceDescription, xcode: xcode, results: results)
                try saveReport(report, output: output, root: root)
                print(report.terminal()+"\n\nEvidence: \(output.path)")
                return report.exitCode
                }
            }
            let derived = URL(fileURLWithPath: options.values["--derived-data"] ??
                FileManager.default.temporaryDirectory.appendingPathComponent("a11ygate-derived-\(UUID().uuidString)").path)
            print("Building device test runner…")
            let buildCode = try process(["xcodebuild", "build-for-testing", "-project", root.appendingPathComponent("ios/A11yGateDemo.xcodeproj").path,
                "-scheme", "A11yGateDemo", "-destination", "generic/platform=iOS", "-derivedDataPath", derived.path,
                "-allowProvisioningUpdates", "DEVELOPMENT_TEAM=\(team)", "COMPILER_INDEX_STORE_ENABLE=NO"], root: root, log: output.appendingPathComponent("build.log"), timeout: 600)
            guard buildCode == 0 else { throw GateError.interrupted("Build failed; inspect build.log") }
            let products = derived.appendingPathComponent("Build/Products")
            guard let runFile = try FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "xctestrun" }) else {
                throw GateError.interrupted("Build produced no xctestrun")
            }
            var server: PlannerServer?
            let metrics = APICallRecorder()
            if planner == "astra" && command == "test" {
                let env = ProcessInfo.processInfo.environment
                let transport = try OpenAITransport(key: env["OPENAI_API_KEY"] ?? "", model: env["A11YGATE_MODEL"] ?? "gpt-6-astra", recorder: metrics)
                let session = PlanningSession(workflows: request.workflows, transport: transport)
                server = try PlannerServer(host: try options.required("--agent-host")) { input in try await session.next(input) }
                server?.start()
            }
            defer { server?.stop(); try? configureRun(at: runFile, request: request, probe: command == "probe") }
            try configureRun(at: runFile, request: request, probe: command == "probe", connection: server?.connection)
            let lock = try DeviceLock(device: xcodeDevice)
            defer { lock.release() }
            print("Running on \(deviceDescription)…")
            let bundle = output.appendingPathComponent("run.xcresult")
            let testArgs = ["xcodebuild", "test-without-building", "-xctestrun", runFile.path,
                "-destination", "platform=iOS,id=\(xcodeDevice)", "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-device-destinations", "1",
                "-resultBundlePath", bundle.path]
            let testCode = try await Task.detached {
                try process(testArgs, root: root, log: output.appendingPathComponent("test.log"), timeout: 1800)
            }.value
            if planner == "astra" { try writeJSON(await metrics.snapshot(), to: output.appendingPathComponent("api-usage.json")) }
            let attachments = output.appendingPathComponent("attachments")
            _ = try capture(["xcrun", "xcresulttool", "export", "attachments", "--path", bundle.path, "--output-path", attachments.path], root: root, log: output.appendingPathComponent("export.log"))
            let files = try FileManager.default.contentsOfDirectory(at: attachments, includingPropertiesForKeys: nil)
            if command == "probe" {
                let capabilities = files.compactMap { try? JSONDecoder().decode(CapabilityEvidence.self, from: Data(contentsOf: $0)) }
                let succeeded = testCode == 0 && capabilities.count == 1 && capabilities[0].usable
                let objects = try capabilities.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
                let record: [String: Any] = ["kind": "a11ygate-probe-summary", "device": deviceDescription, "xcode": xcode,
                    "capabilitiesVerified": succeeded, "capabilities": objects,
                    "note": succeeded ? "Navigation, focus activation and XCTest text injection observed; VoiceOver keyboard use not tested." : "Required capabilities not verified. Inspect test.log for skip or failure."]
                try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("probe.json"))
                print("Probe: \(succeeded ? "ACTIVATION OBSERVED" : "NOT VERIFIED")\nEvidence: \(output.path)")
                return succeeded ? 0 : 2
            }
            let all = files.compactMap { try? JSONDecoder().decode(WorkflowResult.self, from: Data(contentsOf: $0)) }
            for workflow in request.workflows {
                let matching = all.filter { $0.kind == "a11ygate-workflow-v2" && $0.workflow == workflow && $0.mode == mode }
                guard matching.count == 1 else { throw GateError.interrupted("Missing or duplicate evidence for \(workflow.id)") }
                results.append(matching[0])
            }
            if testCode != 0 { infrastructure = "XCTest exited \(testCode); inspect test.log. Workflow results cannot establish a clean run." }
        } catch { infrastructure = error.localizedDescription }
        for workflow in request.workflows where !results.contains(where: { $0.workflow.id == workflow.id }) {
            results.append(WorkflowResult(workflow: workflow, mode: mode, status: .inconclusive,
                                          diagnosis: Diagnosis(reason: infrastructure ?? "Missing runner evidence")))
        }
        let report = RunReport(mode: mode, fixed: request.fixed, device: deviceDescription, xcode: xcode, results: results, infrastructureError: infrastructure)
        try saveReport(report, output: output, root: root)
        print(report.terminal()+"\n\nEvidence: \(output.path)")
        return report.exitCode
    }
    static func configureRun(at url: URL, request: RunRequest, probe: Bool, connection: PlannerConnection? = nil) throws {
        guard var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else { throw GateError.invalid("Unsupported xctestrun format") }
        let encoded = try JSONEncoder().encode(request).base64EncodedString()
        let bridge = try connection.map { try JSONEncoder().encode($0).base64EncodedString() }
        func configure(_ original: [String: Any]) -> [String: Any] {
            var target = original
            var env = target["EnvironmentVariables"] as? [String: String] ?? [:]
            env.removeValue(forKey: "OPENAI_API_KEY")
            env["A11YGATE_RUN_JSON"] = encoded
            env["A11YGATE_PLANNER_CONNECTION"] = bridge
            target["EnvironmentVariables"] = env
            target["OnlyTestIdentifiers"] = probe ? ["CapabilityProbeTests"] : ["WorkflowTests/testConfiguredWorkflows"]
            target["SystemAttachmentLifetime"] = "deleteAlways"
            target["PreferredScreenCaptureFormat"] = "screenshot"
            target["UserAttachmentLifetime"] = "keepAlways"
            target["ParallelizationEnabled"] = false
            return target
        }
        if var configurations = plist["TestConfigurations"] as? [[String: Any]] {
            for i in configurations.indices {
                guard let targets = configurations[i]["TestTargets"] as? [[String: Any]] else { continue }
                configurations[i]["TestTargets"] = targets.map(configure)
            }
            plist["TestConfigurations"] = configurations
        } else if let target = plist["A11yGateUITests"] as? [String: Any] {
            plist["A11yGateUITests"] = configure(target)
        } else {
            throw GateError.invalid("Unsupported xctestrun structure")
        }
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func saveReport(_ report: RunReport, output: URL, root: URL) throws {
        var report = report
        let revision = try? capture(["git", "rev-parse", "HEAD"], root: root, log: output.appendingPathComponent("revision.log"))
        let dirty = try? capture(["git", "status", "--porcelain"], root: root, log: output.appendingPathComponent("status.log"))
        report.provenance = ["sourceRevision": revision ?? "uncommitted", "workingTree": dirty.map { $0.isEmpty ? "clean" : "dirty" } ?? "unknown",
                             "runtimeEvidence": report.results.contains { !$0.steps.isEmpty } ? "see per-workflow execution mode" : "preflight only"]
        try? FileManager.default.removeItem(at: output.appendingPathComponent("revision.log"))
        try? FileManager.default.removeItem(at: output.appendingPathComponent("status.log"))
        try writeJSON(report, to: output.appendingPathComponent("report.json"))
        try report.terminal().write(to: output.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        try ReportRenderer.html(report).write(to: output.appendingPathComponent("report.html"), atomically: true, encoding: .utf8)
        try ReportRenderer.markdown(report).write(to: output.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    }
    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    static func capture(_ args: [String], root: URL, log: URL) throws -> String {
        guard try process(args, root: root, log: log, timeout: 60) == 0 else { throw GateError.interrupted("\(args.prefix(3).joined(separator: " ")) failed; see \(log.path)") }
        return try String(contentsOf: log, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func process(_ args: [String], root: URL, log: URL, timeout: TimeInterval) throws -> Int32 {
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args; process.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "OPENAI_API_KEY")
        process.environment = env
        process.standardOutput = handle; process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(100_000) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(5)
            while process.isRunning && Date() < grace { usleep(100_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw GateError.interrupted("Command timed out; inspect \(log.path)")
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
    static let help = """
    A11yGate — Don't claim accessibility. Prove it.

    Run from the repository root:
      swift run a11ygate doctor
      swift run a11ygate probe --device DEVICE_ID --team TEAM_ID
      swift run a11ygate test --device DEVICE_ID --team TEAM_ID
      swift run a11ygate test --device DEVICE_ID --team TEAM_ID --mode functional
      swift run a11ygate test --device DEVICE_ID --team TEAM_ID --mode functional --fixed
      swift run a11ygate report --input artifacts/RUN/report.json
      swift run a11ygate diagnose --input artifacts/RUN/report.json --allow-cloud

    Optional: --experimental-voiceover --planner astra --allow-cloud --agent-host MAC_PRIVATE_IPV4
    Reports: --format html|markdown|terminal; compare --before FILE --after FILE; diagnose --source FILE
    Optional: --config FILE --output NEW_DIRECTORY --derived-data PATH --screenshots --root REPO
    Defaults: VoiceOver mode, broken fixture, no retained screenshots, no cloud calls.
    MVP: only the bundled synthetic app and its three workflow adapters.
    Exit codes: 0 passed; 1 workflow failure; 2 unsupported, inconclusive, or infrastructure failure.
    Functional PASS does not establish VoiceOver readiness.
    """
}

private struct Options {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    init(_ args: [String]) throws {
        let flagNames: Set<String> = ["--fixed", "--screenshots", "--allow-cloud", "--experimental-voiceover"]
        let valueNames: Set<String> = ["--input", "--output", "--root", "--device", "--team", "--mode", "--config", "--derived-data", "--format", "--before", "--after", "--source", "--planner", "--agent-host"]
        var index = 0
        while index < args.count {
            let arg = args[index]
            if flagNames.contains(arg) { flags.insert(arg); index += 1 }
            else if valueNames.contains(arg), index+1 < args.count, !args[index+1].hasPrefix("--"), values[arg] == nil {
                values[arg] = args[index+1]; index += 2
            } else { throw GateError.invalid("Unknown, duplicate, or incomplete option: \(arg)") }
        }
    }
    func required(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty else { throw GateError.invalid("Missing \(key)") }
        return value
    }
}

/// Cooperates with other A11yGate processes. The user's shared-device harness
/// reservation is acquired separately by the agent before running the CLI.
private final class DeviceLock {
    let path: String
    let token = UUID().uuidString
    init(device: String) throws {
        let safe = device.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard safe == device, !safe.isEmpty else { throw GateError.invalid("Invalid device identifier") }
        path = "/private/tmp/a11ygate-\(safe).lock"
        guard mkdir(path, 0o700) == 0 else { throw GateError.interrupted("Device reserved by another A11yGate process: \(path)") }
        do { try token.write(toFile: path+"/owner", atomically: true, encoding: .utf8) }
        catch { rmdir(path); throw error }
    }
    func release() {
        guard (try? String(contentsOfFile: path+"/owner", encoding: .utf8)) == token else { return }
        try? FileManager.default.removeItem(atPath: path+"/owner")
        rmdir(path)
    }
}
