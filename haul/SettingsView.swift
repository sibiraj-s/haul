import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable {
        case general = "General", downloads = "Downloads", network = "Network", notifications = "Notifications", about = "About"

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .downloads: "arrow.down.to.line"
            case .network: "globe"
            case .notifications: "bell"
            case .about: "info.circle"
            }
        }
    }

    static let width: CGFloat = 560

    @AppStorage("settingsPane") private var pane: Pane = .general
    @State private var window: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(pane.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        TrafficLights(window: window, canMinimize: false).padding(.leading, 2).padding(.top, 8)
                    }
                    .padding(.bottom, 8)
                HStack(spacing: 4) {
                    ForEach(Pane.allCases, id: \.self) { p in
                        Button {
                            pane = p
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: p.symbol).font(.system(size: 17))
                                    .frame(height: 20)
                                Text(p.rawValue).font(.system(size: 11))
                            }
                            .foregroundStyle(pane == p ? Theme.accent : Theme.text2)
                            .frame(width: 76, height: 48)
                            .background(RoundedRectangle(cornerRadius: 9).fill(pane == p ? Theme.selg : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(WindowDragArea(window: window))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.sep).frame(height: 0.5) }

            VStack(spacing: 14) {
                switch pane {
                case .general: GeneralSettings()
                case .downloads: DownloadSettings()
                case .network: NetworkSettings()
                case .notifications: NotificationSettings()
                case .about: AboutSettings()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(minHeight: 300, alignment: .top)
        }
        .frame(width: Self.width)
        // Natural height, whatever the window's size; the window follows it (SettingsWindow.fit).
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { SettingsWindow.shared.fit($0) }
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .font(.system(size: 13))
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .background(Theme.win)
        .ignoresSafeArea()
        .background(WindowConfigurator { if window !== $0 { window = $0 } })
    }
}

/// A settings row: title (+ optional caption) on the left, control on the right.
private struct SettingRow<Control: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption {
                    Text(caption).font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
            }
            Spacer()
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct GeneralSettings: View {
    @Bindable private var settings = AppSettings.shared
    private let updater = Updater.shared

    var body: some View {
        DesignGroup {
            SettingRow(title: "Appearance") {
                DesignSegmented(options: Appearance.allCases.map { ($0, $0.label) }, selection: $settings.appearance, minWidth: 56)
            }
            SettingRow(title: "Accent colour") {
                HStack(spacing: 8) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button {
                            settings.accent = choice
                        } label: {
                            Circle()
                                .fill(choice.color)
                                .frame(width: 16, height: 16)
                                .overlay {
                                    if settings.accent == choice {
                                        Circle().strokeBorder(choice.color, lineWidth: 1.5).padding(-3.5)
                                    } else {
                                        Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(choice.rawValue)
                    }
                }
            }
        }
        DesignGroup {
            SettingRow(title: "Show in menu bar", caption: "Progress ring and live speed next to the clock.") {
                DesignSwitch(isOn: $settings.menuBar)
            }
            SettingRow(title: "Show progress on Dock icon") { DesignSwitch(isOn: $settings.dockProgress) }
            SettingRow(title: "Open at login") {
                DesignSwitch(isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            }
        }
        DesignGroup {
            SettingRow(title: "Ask before removing downloads") { DesignSwitch(isOn: $settings.confirmRemove) }
            SettingRow(title: "Remove finished downloads from list") {
                PopUpMenu(options: ListCleanup.allCases.map { ($0, $0.label) }, selection: $settings.removeFinished)
            }
            SettingRow(title: "Remove downloads whose file was deleted", caption: "Also when the file is moved or renamed in Finder.") {
                DesignSwitch(isOn: $settings.removeDeleted)
            }
        }
        DesignGroup {
            SettingRow(title: "Check for updates automatically", caption: "Once a day, from Haul's GitHub releases.") {
                DesignSwitch(isOn: $settings.checkForUpdates)
            }
            SettingRow(title: "Version \(updater.currentVersion)") {
                PillButton(title: updater.isChecking ? "Checking…" : "Check Now", height: 24, fontSize: 12) { updater.checkNow() }
                    .disabled(updater.isChecking)
            }
        }
    }
}

private struct NotificationSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        DesignGroup {
            SettingRow(title: "Download added") { DesignSwitch(isOn: $settings.notifyAdded) }
            SettingRow(title: "Download finished") { DesignSwitch(isOn: $settings.notify) }
            SettingRow(title: "Download failed", caption: "After any automatic retries have run out.") {
                DesignSwitch(isOn: $settings.notifyFailed)
            }
        }
        DesignGroup {
            SettingRow(title: "Only when Haul isn't in front") { DesignSwitch(isOn: $settings.notifyOnlyInBackground) }
        }
    }
}

private struct DownloadSettings: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        DesignGroup {
            SettingRow(title: "Save downloads to") {
                Menu {
                    Button {
                        settings.setDefaultFolder(nil)
                    } label: {
                        Label("Downloads", systemImage: settings.defaultFolder == nil ? "checkmark" : "folder")
                    }
                    if let custom = settings.defaultFolder {
                        Button {} label: { Label(custom.url.lastPathComponent, systemImage: "checkmark") }
                    }
                    Divider()
                    Button("Other…") {
                        Task {
                            if let picked = await SavedFolder.choose(message: "Choose the default folder for downloads.") {
                                settings.setDefaultFolder(picked)
                            }
                        }
                    }
                    Button("Show in Finder") { NSWorkspace.shared.open(settings.baseFolder) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Theme.accent)
                        Text(settings.baseFolder.lastPathComponent)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .controlChrome(RoundedRectangle(cornerRadius: 6))
                    .help(settings.baseFolder.path)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            SettingRow(title: "Sort into folders by kind", caption: "Movies, Music, Pictures, Documents, Archives, Apps.") {
                DesignSwitch(isOn: $settings.autoSort)
            }
            SettingRow(title: "Compute SHA-256 checksums", caption: "Shown in the inspector to compare with the publisher's.") {
                DesignSwitch(isOn: $settings.computeChecksum)
            }
            SettingRow(title: "Use the server's file date", caption: "Files keep the date they last changed on the server.") {
                DesignSwitch(isOn: $settings.useServerDate)
            }
            SettingRow(title: "Record where files came from", caption: "Shown as “Where from” in Finder's Get Info.") {
                DesignSwitch(isOn: $settings.recordSource)
            }
        }
        DesignGroup {
            SettingRow(title: "Simultaneous downloads") {
                HStack(spacing: 10) {
                    Text("\(settings.maxConcurrent)").monospacedDigit().frame(minWidth: 12, alignment: .trailing)
                    VStack(spacing: 0) {
                        stepper("chevron.up") { settings.maxConcurrent = min(8, settings.maxConcurrent + 1) }
                        Rectangle().fill(Theme.ctlB).frame(width: 16, height: 0.5)
                        stepper("chevron.down") { settings.maxConcurrent = max(1, settings.maxConcurrent - 1) }
                    }
                    .controlChrome(RoundedRectangle(cornerRadius: 5))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            SettingRow(title: "Connections per download") {
                DesignSegmented(options: [1, 4, 8, 16].map { ($0, "\($0)") }, selection: $settings.connections, minWidth: 34)
            }
            SettingRow(title: "Prevent sleep while downloading", caption: "The display can still turn off. Closing the lid still sleeps.") {
                DesignSwitch(isOn: $settings.preventSleep)
            }
        }
    }

    private func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 7, weight: .heavy))
                .frame(width: 16, height: 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}

private struct NetworkSettings: View {
    @Bindable private var settings = AppSettings.shared
    private let hours = (0..<24).map { ($0, AppSettings.hourLabel($0)) }

    var body: some View {
        DesignGroup {
            SettingRow(title: "Limit download speed") { DesignSwitch(isOn: $settings.limitOn) }
            HStack(spacing: 12) {
                Text("1 MB/s").font(.system(size: 12)).foregroundStyle(Theme.text2)
                Slider(value: Binding(get: { Double(settings.limitMBps) }, set: { settings.limitMBps = Int($0) }), in: 1...50, step: 1)
                    .controlSize(.small)
                Text("\(settings.limitMBps) MB/s")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 58, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .opacity(settings.limitOn ? 1 : 0.4)
        }
        DesignGroup {
            SettingRow(title: "Only download on a schedule", caption: "Queued downloads only start during these hours.") {
                DesignSwitch(isOn: $settings.scheduleOnly)
            }
            HStack(spacing: 8) {
                Text("From").foregroundStyle(Theme.text2)
                PopUpMenu(options: hours, selection: $settings.scheduleFrom)
                Text("to").foregroundStyle(Theme.text2)
                PopUpMenu(options: hours, selection: $settings.scheduleTo)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .opacity(settings.scheduleOnly ? 1 : 0.4)
            SettingRow(title: "Pause on Personal Hotspot", caption: "Also respects Low Data Mode.") {
                DesignSwitch(isOn: $settings.pauseOnExpensive)
            }
        }
        DesignGroup {
            SettingRow(title: "Retry failed downloads", caption: "Up to \(DownloadStore.maxRetries) times after a dropped connection or server error.") {
                DesignSwitch(isOn: $settings.autoRetry)
            }
            SettingRow(title: "Skip web pages", caption: "Links that open an HTML page instead of a file aren't saved.") {
                DesignSwitch(isOn: $settings.skipWebPages)
            }
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Haul")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 8)
            Text("Version \(Updater.shared.currentVersion)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text("Haul is free and open source. Sponsoring helps keep it that way.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
            PillButton(title: "♥ Sponsor Haul", prominent: true) { NSWorkspace.shared.open(.sponsor) }
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

/// Pop-up button styled like the other controls: current choice with up/down chevrons.
private struct PopUpMenu<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection { Label(option.label, systemImage: "checkmark") } else { Text(option.label) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.label ?? "")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .controlChrome(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
