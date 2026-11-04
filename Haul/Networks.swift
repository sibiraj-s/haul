import Foundation
import Network
import Synchronization
import SystemConfiguration

/// A network interface a download could go over, as `NetworkWatch` sees it.
nonisolated struct NetworkLink: Equatable, Sendable {
    var name: String
    var type: NWInterface.InterfaceType
    /// Personal Hotspot, an Android hotspot or tethering, or Low Data Mode.
    var metered: Bool
    /// The router's hardware address, to tell two links to the same router apart; nil when unknown,
    /// such as with a static address. Not its IP address: separate networks often share one, as
    /// every iPhone hotspot is 172.20.10.1 and many home routers are 192.168.1.1.
    var router: String?
    /// The interface itself, for pinning connections to it.
    var interface: NWInterface? = nil

    /// The links one download can spread its connections over. A connection pinned to an
    /// interface goes around a VPN or proxy, so there are none while one is in use. Metered
    /// links only count where downloads may use metered networks, and only one link per router,
    /// as two links to the same router share its uplink.
    static func usable(_ links: [NetworkLink], vpn: Bool, proxy: Bool, allowMetered: Bool) -> [NetworkLink] {
        guard !vpn, !proxy else { return [] }
        var names = Set<String>()
        var routers = Set<String>()
        return links.filter { link in
            guard link.type == .wifi || link.type == .wiredEthernet, names.insert(link.name).inserted else { return false }
            guard allowMetered || !link.metered else { return false }
            return link.router.map { routers.insert($0).inserted } ?? true
        }
    }
}

extension NetworkLink {
    /// What System Settings calls interface `name`, such as Wi‑Fi or the phone tethered over USB.
    static func displayName(_ name: String) -> String {
        if let known = displayNames.withLock({ $0[name] }) { return known }
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let found =
            interfaces.first { SCNetworkInterfaceGetBSDName($0) as String? == name }
            .flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? } ?? name
        displayNames.withLock { $0[name] = found }
        return found
    }

    private static let displayNames = Mutex<[String: String]>([:])
}

/// What a DHCP lease says about the network it came from.
nonisolated enum NetworkLease {
    struct Lease: Equatable, Sendable {
        /// The router's IP address.
        var router: String?
        /// The router's hardware address, from the ARP table; nil when it isn't there.
        var routerHardware: String?
        /// The lease says the network is metered.
        var metered = false
    }

    /// The last lease read for each interface, with the interface's addresses then and when, for when
    /// reading it fails, and so the hotspot check and `NetworkWatch` reading the same lease for one
    /// network change run `ipconfig` once.
    private static let last = Mutex<[String: (lease: Lease, addresses: Set<Data>, at: Date)]>([:])
    /// How long a lease just read is used as it is, while the interface keeps the same addresses;
    /// a new network gives it new ones.
    static let freshFor: TimeInterval = 1

    /// `interface`'s DHCP lease: its router, and whether it says the network is metered. Android
    /// hotspots, Pixel's among them, say so in the vendor option, which macOS doesn't always act on.
    /// A failed read gives the last lease, so the network doesn't seem to change.
    static func read(_ interface: NWInterface) -> Lease? {
        let addresses = PinnedRequest.addresses(of: interface.name)
        let saved = last.withLock { $0[interface.name] }
        if let saved, saved.addresses == addresses, Date().timeIntervalSince(saved.at) < freshFor { return saved.lease }
        guard var lease = fetch(interface) else { return saved?.lease }
        lease.routerHardware = lease.router.flatMap { hardwareAddress(of: $0, on: interface.name) }
        last.withLock { $0[interface.name] = (lease, addresses, Date()) }
        return lease
    }

    /// Only `ipconfig` shows the vendor option, so read it from its output.
    private static func fetch(_ interface: NWInterface) -> Lease? {
        guard interface.type == .wifi || interface.type == .wiredEthernet else { return nil }
        return run("/usr/sbin/ipconfig", ["getpacket", interface.name]).map(parse)
    }

    /// The hardware address the ARP table has for `ip` on `interface`. macOS checks the router this
    /// way when it joins a network, so it's there then.
    private static func hardwareAddress(of ip: String, on interface: String) -> String? {
        run("/usr/sbin/arp", ["-a", "-n", "-i", interface]).flatMap { hardwareAddress(of: ip, in: $0) }
    }

    /// Reads lines like "? (192.168.1.1) at 68:7f:f0:1d:34:0 on en0 ifscope [ethernet]".
    static func hardwareAddress(of ip: String, in output: String) -> String? {
        for line in output.split(separator: "\n") {
            guard let at = line.firstRange(of: "(\(ip)) at ") else { continue }
            let address = line[at.upperBound...].prefix { $0 != " " }
            return address.contains(":") ? String(address) : nil
        }
        return nil
    }

    /// The output of a command, or nil if it couldn't run or took too long: network updates wait on it.
    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        guard (try? process.run()) != nil else { return nil }
        if exited.wait(timeout: .now() + 2) == .timedOut {
            process.terminate()
            return nil
        }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    static func parse(_ output: String) -> Lease {
        let lines = output.split(separator: "\n").map(String.init)
        let router = lines.first { $0.hasPrefix("router ") }?.split(separator: "{").last?.split(separator: "}").first.map(String.init)
        // The vendor option is a hex dump: "0000  41 4e 44 …  4d 45 …     ANDROID_METERED". Collect
        // the bytes from the hex columns, as the text column can wrap a value across lines.
        var vendor: [UInt8] = []
        if let start = lines.firstIndex(where: { $0.hasPrefix("vendor_specific ") }) {
            for line in lines[(start + 1)...] {
                guard line.count > 6, line.prefix(4).allSatisfy(\.isHexDigit), line.dropFirst(4).hasPrefix("  ") else { break }
                vendor += line.dropFirst(6).prefix(49).split(separator: " ").compactMap { UInt8($0, radix: 16) }
            }
        }
        let marker = Array("ANDROID_METERED".utf8)
        let metered =
            vendor.count >= marker.count
            && (0...(vendor.count - marker.count)).contains { Array(vendor[$0..<($0 + marker.count)]) == marker }
        return Lease(router: router, metered: metered)
    }
}

/// Watches every network the Mac is on, not just the one traffic goes over, for the links a
/// download could use together.
nonisolated final class NetworkWatch: Sendable {
    struct State: Equatable, Sendable {
        var links: [NetworkLink] = []
        /// Traffic goes through a VPN tunnel.
        var vpn = false
        /// The interface traffic goes over by default, skipping a VPN's tunnel.
        var primary: String?
    }

    private let queue = DispatchQueue(label: "Haul.networks")
    private let all = NWPathMonitor()
    /// A path only says whether the interface it prefers is metered, so each kind of interface
    /// gets its own. Two wired links share one, so either being metered marks both.
    private let byType = [NWInterface.InterfaceType.wifi, .wiredEthernet].map { ($0, NWPathMonitor(requiredInterfaceType: $0)) }
    /// The latest path from each monitor.
    private let paths = Mutex<(all: NWPath?, byType: [NWInterface.InterfaceType: NWPath])>((nil, [:]))

    private let last = Mutex<State?>(nil)
    private let scheduled = Mutex(false)
    private let changed: @Sendable (State) -> Void

    /// `changed` is called on a background queue, in order, whenever the state changes.
    init(changed: @escaping @Sendable (State) -> Void) {
        self.changed = changed
        all.pathUpdateHandler = { [weak self] path in
            self?.paths.withLock { $0.all = path }
            self?.update()
        }
        for (type, monitor) in byType {
            monitor.pathUpdateHandler = { [weak self] path in
                self?.paths.withLock { $0.byType[type] = path }
                self?.update()
            }
        }
    }

    /// One change usually brings an update from each monitor; they're taken together, so each
    /// lease is read once.
    private func update() {
        guard
            scheduled.withLock({ waiting in
                defer { waiting = true }
                return !waiting
            })
        else { return }
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            scheduled.withLock { $0 = false }
            let (all, byType) = paths.withLock { ($0.all, $0.byType) }
            let state = Self.state(all: all, byType: byType)
            guard
                last.withLock({ old in
                    defer { old = state }
                    return old != state
                })
            else { return }
            changed(state)
        }
    }

    func start() {
        all.start(queue: queue)
        for (_, monitor) in byType { monitor.start(queue: queue) }
    }

    private static func state(all: NWPath?, byType: [NWInterface.InterfaceType: NWPath]) -> State {
        guard let all, all.status == .satisfied else { return State() }
        // A full-tunnel VPN puts its tunnel first; one that only carries some traffic, like
        // Tailscale without an exit node, lists it after the interfaces it runs over.
        let vpn = all.availableInterfaces.first?.type == .other
        let links = all.availableInterfaces.compactMap { interface -> NetworkLink? in
            guard let path = byType[interface.type], path.status == .satisfied else { return nil }
            let lease = NetworkLease.read(interface)
            return NetworkLink(
                name: interface.name, type: interface.type,
                metered: path.isExpensive || path.isConstrained || lease?.metered == true,
                router: lease?.routerHardware, interface: interface)
        }
        let primary = all.availableInterfaces.first { $0.type != .other && $0.type != .loopback }?.name
        return State(links: links, vpn: vpn, primary: primary)
    }
}
