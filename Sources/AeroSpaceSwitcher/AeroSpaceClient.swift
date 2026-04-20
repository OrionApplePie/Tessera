import Foundation

struct AeroSpaceClient {
    var executableCandidates = [
        "/opt/homebrew/bin/aerospace",
        "/usr/local/bin/aerospace",
        "aerospace"
    ]

    func listAllWorkspaceIDs() throws -> [String] {
        let output = try runAeroSpace(arguments: ["list-workspaces", "--all"])
        return Self.splitNonEmptyLines(output)
    }

    func listFocusedWorkspaceIDs() throws -> [String] {
        let output = try runAeroSpace(arguments: ["list-workspaces", "--focused"])
        return Self.splitNonEmptyLines(output)
    }

    func listWorkspaces() throws -> [Workspace] {
        let focused = Set(try listFocusedWorkspaceIDs())
        return try listAllWorkspaceIDs().map { id in
            Workspace(id: id, isFocused: focused.contains(id))
        }
    }

    func listWindows() throws -> [AeroSpaceWindow] {
        let format = "%{workspace}|%{app-name}|%{window-title}"
        let output = try runAeroSpace(arguments: ["list-windows", "--all", "--format", format])

        return Self.splitNonEmptyLines(output).map { line in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            let workspace = parts.count > 0 ? String(parts[0]) : ""
            let appName = parts.count > 1 ? String(parts[1]) : ""
            let title = parts.count > 2 ? String(parts[2]) : ""
            return AeroSpaceWindow(workspace: workspace, appName: appName, title: title)
        }
    }

    func switchWorkspace(_ workspaceID: String) throws {
        _ = try runAeroSpace(arguments: ["workspace", workspaceID])
    }

    private func runAeroSpace(arguments: [String]) throws -> String {
        var lastError: Error?

        for candidate in executableCandidates {
            do {
                if candidate.contains("/") {
                    return try runProcess(executable: candidate, arguments: arguments)
                }

                return try runProcess(executable: "/usr/bin/env", arguments: [candidate] + arguments)
            } catch let error as AeroSpaceClientError {
                if case .commandFailed = error {
                    throw error
                }

                lastError = error
            } catch {
                lastError = error
            }
        }

        throw AeroSpaceClientError.aeroSpaceNotFound(
            lastError?.localizedDescription ?? "AeroSpace executable was not found"
        )
    }

    private func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw AeroSpaceClientError.processLaunchFailed(
                "Failed to launch \(executable): \(error.localizedDescription)"
            )
        }

        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        let output = String(decoding: outputData, as: UTF8.self)
        let errorOutput = String(decoding: errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw AeroSpaceClientError.commandFailed(
                errorOutput.isEmpty ? "AeroSpace command failed" : errorOutput
            )
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func splitNonEmptyLines(_ text: String) -> [String] {
        text
            .split(whereSeparator: { character in
                character.unicodeScalars.allSatisfy(CharacterSet.newlines.contains)
            })
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum AeroSpaceClientError: Error, CustomStringConvertible {
    case aeroSpaceNotFound(String)
    case processLaunchFailed(String)
    case commandFailed(String)

    var description: String {
        switch self {
        case .aeroSpaceNotFound(let message),
             .processLaunchFailed(let message),
             .commandFailed(let message):
            return message
        }
    }
}
