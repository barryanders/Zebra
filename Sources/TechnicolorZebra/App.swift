import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TechnicolorZebraCore

enum AppLinks {
    static let coffee = URL(string: "https://buymeacoffee.com/barryanders")!
}

struct QueueItem: Identifiable {
    let id = UUID()
    let source: URL
    var output: URL?
    var fraction = 0.0
    var status = "Ready"
    var finished = false
    var error = false
}

@MainActor final class AppModel: ObservableObject {
    @Published var items: [QueueItem] = []
    @Published var running = false
    @Published var notice: String?
    private var runner: ProcessRunner?
    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL {
            let normalized = url.standardizedFileURL
            if !items.contains(where: { $0.source == normalized }) { items.append(QueueItem(source: normalized)) }
        }
    }
    func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        // Matroska may not be registered as UTType.movie on a clean Mac.
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func cancel() { runner?.cancel() }
    func clear() { if !running { items.removeAll(); notice = nil } }
    func start() {
        guard !running, !items.isEmpty else { return }
        notice = nil
        let runner = ProcessRunner()
        self.runner = runner
        running = true
        let pending = items.filter { !$0.finished }
        Task {
            do {
                let tools = try await Task.detached {
                    let tools = try VideoTools.discover()
                    try tools.validate(using: runner)
                    return tools
                }.value
                let converter = Converter(tools: tools, runner: runner)
                // Hold no-sleep assertion only while a user-started conversion is active.
                let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Converting HDR videos")
                defer { ProcessInfo.processInfo.endActivity(activity) }
                for item in pending {
                    do {
                        try runner.checkCancellation()
                        if let index = items.firstIndex(where: { $0.id == item.id }) {
                            items[index].error = false
                            items[index].fraction = 0
                            items[index].status = "Checking video…"
                        }
                        let output = try await Task.detached {
                            try converter.convert(item.source) { progress in
                                Task { @MainActor in
                                    if let index = self.items.firstIndex(where: { $0.id == item.id }), !self.items[index].finished, !self.items[index].error, self.running {
                                        self.items[index].fraction = progress.fraction
                                        self.items[index].status = progress.stage
                                    }
                                }
                            }
                        }.value
                        if let index = items.firstIndex(where: { $0.id == item.id }) {
                            items[index].output = output
                            items[index].finished = true
                            items[index].fraction = 1
                            items[index].status = "SDR copy ready"
                            items[index].error = false
                        }
                    } catch {
                        if let index = items.firstIndex(where: { $0.id == item.id }) {
                            items[index].status = error.localizedDescription
                            items[index].error = true
                        }
                        if case TechnicolorZebraError.cancelled = error { break }
                    }
                }
            } catch { notice = error.localizedDescription }
            running = false
            self.runner = nil
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var targeted = false
    var body: some View {
        VStack(spacing: 18) {
            Text("HDR to SDR for Mac").font(.system(size: 10, weight: .medium, design: .rounded)).tracking(1).foregroundStyle(.secondary)
            Button(action: model.browse) {
                VStack(spacing: 14) {
                    if let url = Bundle.main.url(forResource: "Zebra", withExtension: "png"),
                       let icon = NSImage(contentsOf: url) {
                        Image(nsImage: icon).resizable().interpolation(.high)
                            .scaledToFit().frame(width: 82, height: 82)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "film").font(.system(size: 32)).frame(width: 82, height: 82)
                            .accessibilityHidden(true)
                    }
                    Text("Drop. Convert. Done.").font(.system(size: 21, weight: .medium)).tracking(-0.5)
                    Text("Drop videos here, or click to browse.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add videos")
            .background(targeted ? Color.accentColor.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.add([url]) } }
                    }
                }
                return true
            }
            if !model.items.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(model.items) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: item.output == nil ? "film" : "checkmark.circle")
                                        .foregroundStyle(item.output == nil ? Color.secondary : Color.accentColor)
                                    Text(item.source.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                    if let output = item.output {
                                        Button { NSWorkspace.shared.activateFileViewerSelecting([output]) } label: { Image(systemName: "folder") }
                                            .buttonStyle(.borderless).help("Show SDR copy in Finder")
                                            .accessibilityLabel("Show \(output.lastPathComponent) in Finder")
                                    }
                                }.font(.system(size: 12))
                                Text(item.status).font(.system(size: 11)).foregroundStyle(item.error ? Color.red : .secondary).textSelection(.enabled)
                                if model.running && !item.finished && !item.error { ProgressView(value: item.fraction).controlSize(.small) }
                            }
                        }
                    }.padding(2)
                }.frame(height: min(220, CGFloat(model.items.count) * 86))
            }
            if let notice = model.notice { Text(notice).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled) }
            Button {
                if model.running { model.cancel() } else { model.start() }
            } label: {
                Text(model.running ? "Cancel conversion" : "Make SDR \(model.items.count > 1 ? "copies" : "copy")")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!model.running && (model.items.isEmpty || model.items.allSatisfy(\.finished)))
            VStack(spacing: 5) {
                Text("Originals stay untouched.")
                Text("SDR copies save beside them as MKV.")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            if !model.items.isEmpty && !model.running {
                Button("Clear list", action: model.clear).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Link(destination: AppLinks.coffee) {
                Label("Buy me a coffee", systemImage: "cup.and.saucer")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
                .help("Optional support — opens Buy Me a Coffee in your browser")
        }.padding(26).frame(width: 340)
            .background(Color(nsColor: .windowBackgroundColor))
            .tint(Color(red: 0.28, green: 0.43, blue: 0.55))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in Self.model?.add(urls) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.model?.running == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A conversion is still running"
        alert.informativeText = "Cancel it in Zebra before quitting. Your original video is safe."
        alert.addButton(withTitle: "Keep Zebra open")
        alert.runModal()
        return .terminateCancel
    }
}

@main struct TechnicolorZebraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Zebra", id: "main") {
            ContentView().environmentObject(model)
                .onAppear { AppDelegate.model = model }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Add videos…", action: model.browse).keyboardShortcut("o") }
            CommandGroup(replacing: .appSettings) { }
            CommandGroup(after: .help) {
                Button("Buy me a coffee…") { NSWorkspace.shared.open(AppLinks.coffee) }
            }
        }
    }
}
