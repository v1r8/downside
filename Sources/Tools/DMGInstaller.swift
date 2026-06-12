import SwiftUI
import AppKit

/// Instala o app contido num .dmg: monta, copia para Aplicativos e
/// desmonta.
enum DMGInstaller {
    enum InstallError: Error {
        case toolFailed
        case noAppFound
    }

    static func installedAppPath(for dmg: URL) -> String? {
        let path = UserDefaults.standard.string(forKey: "dmgInstalled.\(dmg.lastPathComponent)")
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    static func install(dmg: URL) async throws -> URL {
        let attachOutput = try await run(
            "/usr/bin/hdiutil",
            ["attach", dmg.path, "-nobrowse", "-readonly", "-plist"]
        )
        guard let mountPoint = mountPoint(from: attachOutput) else {
            throw InstallError.toolFailed
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: mountPoint),
                includingPropertiesForKeys: nil
            )
            guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
                throw InstallError.noAppFound
            }

            let applications = FileManager.default.isWritableFile(atPath: "/Applications")
                ? URL(fileURLWithPath: "/Applications")
                : Prefs.supportDirectory("").deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Applications", isDirectory: true)
            try? FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

            let destination = applications.appendingPathComponent(app.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: app, to: destination)
            }

            _ = try? await run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"])
            UserDefaults.standard.set(destination.path, forKey: "dmgInstalled.\(dmg.lastPathComponent)")
            return destination
        } catch {
            _ = try? await run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"])
            throw error
        }
    }

    private static func mountPoint(from plistData: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData, format: nil
        ) as? [String: Any],
            let entities = plist["system-entities"] as? [[String: Any]]
        else { return nil }
        return entities.compactMap { $0["mount-point"] as? String }.first
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: InstallError.toolFailed)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Pill ao lado de arquivos .dmg: "Instalar" → progresso → "Abrir".
struct DMGActionButton: View {
    let url: URL
    let scale: CGFloat

    private enum Phase: Equatable {
        case install
        case working
        case open(String)
        case failed
    }

    @State private var phase: Phase = .install

    var body: some View {
        Group {
            switch phase {
            case .install:
                pill("arrow.down.app", "Instalar") {
                    Task { await install() }
                }
            case .working:
                HStack(spacing: 4 * scale) {
                    ProgressView().controlSize(.small)
                    Text("Instalando…")
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(.secondary)
                }
            case .open(let path):
                pill("arrow.up.forward.app", "Abrir") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
            case .failed:
                Text("Falhou")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if let path = DMGInstaller.installedAppPath(for: url) {
                phase = .open(path)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: phase)
    }

    private func pill(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 10 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 3 * scale)
                .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(.borderless)
    }

    private func install() async {
        phase = .working
        do {
            let app = try await DMGInstaller.install(dmg: url)
            phase = .open(app.path)
        } catch {
            phase = .failed
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            phase = .install
        }
    }
}
