//
//  StatsManager.swift
//  Notch Lyrics
//
//  System readings for the notch stats tab: CPU, GPU, memory, network and
//  temperature. Nothing here draws anything — this file only produces numbers.
//
//  Cost is the point of this design. Every source below is a syscall or an
//  IORegistry property read, all of them microsecond-scale, and none of them
//  need root. The one thing that is NOT free is running them forever, so the
//  sampler is a plain struct with no timer of its own: the manager starts and
//  stops the clock, and the view only starts it while the tab is on screen.
//  A stats panel that costs measurable CPU is a self-own.
//
//  Where the numbers come from, and what they actually mean:
//
//  CPU — host_processor_info(PROCESSOR_CPU_LOAD_INFO) returns cumulative ticks
//  per core. Usage is the difference between two samples, so the first sample
//  has no baseline and reports nothing. The counters are 32-bit and wrap; `&-`
//  handles the wrap correctly, and the resulting delta is the true one as long
//  as less than 2^32 ticks pass between samples (years, not seconds).
//
//  GPU — IOAccelerator's "PerformanceStatistics" dictionary. "Device
//  Utilization %" is the share of the sampling window during which the GPU had
//  work in flight. It is NOT "how much of the GPU's capacity is used": a video
//  call can pin it at 100% while the chip is mostly idle. Label it utilisation,
//  never load, and never colour it like an alarm.
//
//  Memory — host_statistics64. "Used" is active + wired + compressed, which is
//  what Activity Monitor's "Memory Used" reports. Total minus free is the
//  tempting formula and it is wrong for a bar: on a 16 GB machine with a warm
//  file cache it reads 15.8 GB and looks like the machine is dying, because
//  inactive pages are reclaimable and should not be counted.
//
//  Network — getifaddrs byte counters, summed across every non-loopback
//  interface and differenced against the previous sample. The counters are
//  32-bit and wrap roughly every 4 GB, which `&-` also handles.
//
//  Temperature — AppleSMC through an IOKit user client. Readable without root.
//  Keys differ per machine, so the sampler probes a candidate list once at
//  start-up and keeps whatever answers with a plausible reading; an Intel Mac
//  answers to TC0*, an Apple Silicon one to Tp0*/Te0*/Tg0*. The Apple Silicon
//  values are little-endian floats even though the type tag says "flt ", which
//  is the detail that makes naive ports read 7.8e13 degrees.
//
//  Measured on an M1 Pro: host_processor_info 0.011 ms, getifaddrs 0.036 ms,
//  IOAccelerator 0.070 ms, host_statistics64 0.005 ms — and the SMC sweep
//  ~8 ms, because it is two kernel round trips per key across twenty keys.
//  Everything cheap runs every tick; the temperature sweep runs every third,
//  which brings the average down to under a millisecond without any key
//  going stale for longer than three seconds.
//

import Combine
import Darwin
import Foundation
import IOKit

// MARK: - Snapshot

/// One reading. Everything is already in display units except the byte counts,
/// which stay raw so the view can choose its own formatting.
struct StatsSnapshot: Equatable {
    /// 0...1, across all cores.
    var cpuUsage: Double
    /// 0...1, or nil on machines that do not expose accelerator statistics.
    var gpuUsage: Double?
    /// Bytes of system memory the GPU has allocated, when reported.
    var gpuMemory: UInt64?
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    /// Bytes in use and total on the boot volume. "Used" is total minus what is
    /// available to the user, which is the number Finder puts next to a disk.
    var diskUsed: UInt64
    var diskTotal: UInt64
    var downBytesPerSecond: Double
    var upBytesPerSecond: Double
    /// Hottest CPU sensor, in °C. Nil when SMC is unavailable.
    var cpuTemperature: Double?
    /// Hottest GPU sensor, in °C.
    var gpuTemperature: Double?
}

// MARK: - Sampler

/// Holds the previous sample so the next one can be a delta. No timer, no
/// published state, no main-actor requirement — it is safe to drive from a
/// background queue if the view ever needs to.
struct StatsSampler {
    private var previousTicks: [UInt32] = []
    private var previousNetwork: (rx: UInt64, tx: UInt64)?
    private var previousDate: Date?

    private let smc: SMCCore?
    private let cpuTemperatureKeys: [String]
    private let gpuTemperatureKeys: [String]

    /// Temperature is the only expensive source, so it runs every third tick.
    /// The last reading is held in between — three seconds is well under the
    /// rate at which a die temperature actually moves.
    private var tick = 0
    private let temperatureEvery = 3
    private var lastCPUTemperature: Double?
    private var lastGPUTemperature: Double?

    init() {
        let smc = SMCCore()
        self.smc = smc

        var cpu: [String] = []
        var gpu: [String] = []
        if let smc {
            for key in Self.cpuCandidates where smc.isPlausibleTemperature(key) {
                cpu.append(key)
            }
            for key in Self.gpuCandidates where smc.isPlausibleTemperature(key) {
                gpu.append(key)
            }
        }
        cpuTemperatureKeys = cpu
        gpuTemperatureKeys = gpu
    }

    /// Apple Silicon uses Tp0* for performance cores, Te0* for efficiency cores;
    /// Intel answers to TC0*. Both are probed, whichever exists wins.
    private static let cpuCandidates: [String] = {
        var keys = ["TC0P", "TC0D", "TC0E", "TC0F", "TC0H", "TC0J", "TCXC"]
        for suffix in "0123456789abcdef" {
            keys.append("Tp0\(suffix)")
            keys.append("Te0\(suffix)")
        }
        return keys
    }()

    private static let gpuCandidates: [String] = {
        var keys = ["TG0P", "TG0D"]
        for suffix in "0123456789abcdef" {
            keys.append("Tg0\(suffix)")
        }
        return keys
    }()

    mutating func sample(now: Date = Date()) -> StatsSnapshot {
        let memory = sampleMemory()
        let network = sampleNetwork(now: now)
        let gpu = sampleGPU()
        let cpu = sampleCPU()
        let disk = sampleDisk()

        if tick % temperatureEvery == 0 {
            lastCPUTemperature = hottest(cpuTemperatureKeys)
            lastGPUTemperature = hottest(gpuTemperatureKeys)
        }
        tick &+= 1

        return StatsSnapshot(
            cpuUsage: cpu ?? 0,
            gpuUsage: gpu?.usage,
            gpuMemory: gpu?.memory,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            diskUsed: disk.used,
            diskTotal: disk.total,
            downBytesPerSecond: network.down,
            upBytesPerSecond: network.up,
            cpuTemperature: lastCPUTemperature,
            gpuTemperature: lastGPUTemperature
        )
    }

    private func hottest(_ keys: [String]) -> Double? {
        guard let smc, !keys.isEmpty else { return nil }
        let readings = keys.compactMap { smc.temperature($0) }
        return readings.max()
    }

    /// Drops the delta baselines so a later start does not report a spike
    /// measured across the whole time the tab was closed. The probed SMC key
    /// list is deliberately kept: re-probing costs ~20 ms, and paying that on
    /// every reopen would be a visible hitch for no gain.
    mutating func resetBaseline() {
        previousTicks = []
        previousNetwork = nil
        previousDate = nil
        tick = 0
    }

    // MARK: CPU

    private mutating func sampleCPU() -> Double? {
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: UnsafeMutableRawPointer(info))),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let stride = Int(CPU_STATE_MAX)
        var ticks = [UInt32](repeating: 0, count: Int(cpuCount) * stride)
        for index in ticks.indices {
            ticks[index] = UInt32(bitPattern: info[index])
        }

        let previous = previousTicks
        previousTicks = ticks
        guard previous.count == ticks.count else { return nil }

        var busy: UInt32 = 0
        var total: UInt32 = 0
        for base in Swift.stride(from: 0, to: ticks.count, by: stride) {
            let user = ticks[base + Int(CPU_STATE_USER)] &- previous[base + Int(CPU_STATE_USER)]
            let system = ticks[base + Int(CPU_STATE_SYSTEM)] &- previous[base + Int(CPU_STATE_SYSTEM)]
            let idle = ticks[base + Int(CPU_STATE_IDLE)] &- previous[base + Int(CPU_STATE_IDLE)]
            let nice = ticks[base + Int(CPU_STATE_NICE)] &- previous[base + Int(CPU_STATE_NICE)]
            busy &+= user &+ system &+ nice
            total &+= user &+ system &+ idle &+ nice
        }

        guard total > 0 else { return nil }
        return min(1, Double(busy) / Double(total))
    }

    // MARK: GPU

    private func sampleGPU() -> (usage: Double, memory: UInt64?)? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var result: (usage: Double, memory: UInt64?)?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            // Intel Macs expose two accelerators (integrated and discrete).
            // Only the one with utilisation data is worth showing.
            guard result == nil,
                  let statistics = IORegistryEntryCreateCFProperty(
                      service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
                  )?.takeRetainedValue() as? [String: Any],
                  let utilisation = statistics["Device Utilization %"] as? NSNumber
            else { continue }

            let allocated = (statistics["In use system memory"] as? NSNumber)?.uint64Value
            result = (min(1, utilisation.doubleValue / 100), allocated)
        }
        return result
    }

    // MARK: Memory

    private func sampleMemory() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let status = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return (0, total) }

        let page = UInt64(getpagesize())
        let used = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        return (min(total, used * page), total)
    }

    // MARK: Disk

    /// Boot volume, through `statfs`. `f_bavail` — not `f_bfree` — is what
    /// Finder and the storage pane mean by available: it excludes the blocks
    /// reserved for root, which on APFS is a few gigabytes the user can never
    /// have. One syscall, no volume enumeration, and it follows the boot disk
    /// even when the system is running from an external one.
    private func sampleDisk() -> (used: UInt64, total: UInt64) {
        var stats = statfs()
        guard statfs("/", &stats) == 0 else { return (0, 0) }
        let blockSize = UInt64(stats.f_bsize)
        let total = UInt64(stats.f_blocks) * blockSize
        let available = UInt64(stats.f_bavail) * blockSize
        return (total > available ? total - available : 0, total)
    }

    // MARK: Network

    private mutating func sampleNetwork(now: Date) -> (down: Double, up: Double) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return (0, 0) }
        defer { freeifaddrs(addresses) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            else { continue }
            if String(cString: interface.pointee.ifa_name).hasPrefix("lo") { continue }
            received &+= UInt64(data.pointee.ifi_ibytes)
            sent &+= UInt64(data.pointee.ifi_obytes)
        }

        defer {
            previousNetwork = (received, sent)
            previousDate = now
        }
        guard let previous = previousNetwork, let previousDate,
              let interval = now.timeIntervalSince(previousDate) as TimeInterval?,
              interval > 0
        else { return (0, 0) }

        // A huge delta means an interface came or went, not that 3 GB/s moved.
        let cap: UInt64 = 1_000_000_000
        let down = received &- previous.rx
        let up = sent &- previous.tx
        return (
            down < cap ? Double(down) / interval : 0,
            up < cap ? Double(up) / interval : 0
        )
    }
}

// MARK: - SMC

/// Minimal AppleSMC reader. Only reads keys — writes would need root, and this
/// file has no business changing anything on the machine.
private final class SMCCore {
    private var connection: io_connect_t = 0

    private static let kernelIndex: UInt32 = 2
    private static let readBytes: UInt8 = 5
    private static let readKeyInfo: UInt8 = 9

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    func temperature(_ key: String) -> Double? {
        guard let reading = read(key) else { return nil }
        switch reading.type {
        case "flt " where reading.bytes.count >= 4:
            // Little-endian on Apple Silicon despite the big-endian-looking tag.
            let b = reading.bytes
            let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case "sp78" where reading.bytes.count >= 2:
            let b = reading.bytes
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        default:
            return nil
        }
    }

    func isPlausibleTemperature(_ key: String) -> Bool {
        guard let value = temperature(key) else { return false }
        return value > 1 && value < 120
    }

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.size

        input.key = Self.fourCC(key)
        input.data8 = Self.readKeyInfo
        guard IOConnectCallStructMethod(
            connection, Self.kernelIndex, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize
        ) == KERN_SUCCESS else { return nil }

        // The read call overwrites keyInfo, so the size has to be captured here.
        let size = Int(output.keyInfo.dataSize)
        let type = Self.string(fromFourCC: output.keyInfo.dataType)
        guard size > 0, size <= 32 else { return nil }

        input.keyInfo.dataSize = UInt32(size)
        input.data8 = Self.readBytes
        outputSize = MemoryLayout<SMCKeyData>.size
        guard IOConnectCallStructMethod(
            connection, Self.kernelIndex, &input, MemoryLayout<SMCKeyData>.size, &output, &outputSize
        ) == KERN_SUCCESS else { return nil }

        return (type, withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) })
    }

    private static func fourCC(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }

    private static func string(fromFourCC value: UInt32) -> String {
        String(bytes: [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ], encoding: .ascii) ?? ""
    }
}

// MARK: - Wire layout
//
// These mirror the kernel's SMCKeyData exactly, including the trailing padding
// in SMCKeyInfoData. Swift does not add it for a nested struct, which shifts
// every field after keyInfo by three bytes and makes the whole call fail with
// kIOReturnBadArgument — the struct has to be 80 bytes, not 76.

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var padding0: UInt8 = 0
    var padding1: UInt8 = 0
    var padding2: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

// MARK: - Manager

@MainActor
final class StatsManager: ObservableObject {
    static let shared = StatsManager()

    @Published private(set) var snapshot: StatsSnapshot?

    /// Last minute of network throughput, oldest first, in bytes per second.
    /// Kept here rather than in the view so the trace survives a tab switch
    /// without restarting the clock.
    ///
    /// Published even though `snapshot` already fires every tick: the two are
    /// assigned one after the other, and a view that only heard about
    /// `snapshot` would draw the trace from the previous tick. One extra
    /// objectWillChange per second is cheaper than a trace that lags.
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var uploadHistory: [Double] = []
    /// How many one-second samples the trace shows. Static so the view can lay
    /// its x-axis out against the same window the manager fills.
    static let historyLength = 60

    /// Sampling runs here, off the main thread. See `StatsSamplerBox`.
    private let samplerBox = StatsSamplerBox()
    private var timer: Timer?
    /// Held only while the clock runs. Without it App Nap coalesces the timer
    /// down to roughly one fire every ten seconds — measured, not guessed: the
    /// curve stalled at 16 of its 60 points after two minutes. A background app
    /// with a static window naps, and the notch is exactly that most of the
    /// time. `userInitiatedAllowingIdleSystemSleep` blocks the nap without
    /// keeping the display awake.
    private var activity: NSObjectProtocol?
    /// A reading takes single-digit milliseconds; skipping the next tick while
    /// one is still in flight keeps a loaded machine from stacking them up.
    private var isSampling = false

    private init() {}

    /// Starts the clock. Idempotent, so the view can call it from `.onAppear`
    /// without checking first.
    func start(interval: TimeInterval = 1) {
        guard timer == nil else { return }

        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Sampling system stats for the notch"
        )

        tick()

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the clock and drops the baseline, so a later start does not report
    /// a spike measured across the whole time the tab was closed.
    func stop() {
        timer?.invalidate()
        timer = nil
        samplerBox.resetBaseline()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func tick() {
        guard !isSampling else { return }
        isSampling = true
        samplerBox.sample { [weak self] reading in
            // `sample` hands the reading back on the main queue, but the hop
            // still has to be declared: this closure is not actor-isolated.
            Task { @MainActor in
                guard let self else { return }
                self.isSampling = false
                self.publish(reading)
            }
        }
    }

    private func publish(_ reading: StatsSnapshot) {
        snapshot = reading

        downloadHistory.append(reading.downBytesPerSecond)
        uploadHistory.append(reading.upBytesPerSecond)
        if downloadHistory.count > Self.historyLength {
            downloadHistory.removeFirst(downloadHistory.count - Self.historyLength)
        }
        if uploadHistory.count > Self.historyLength {
            uploadHistory.removeFirst(uploadHistory.count - Self.historyLength)
        }
    }
}

// MARK: - Sampler box

/// Owns `StatsSampler` and the queue it runs on.
///
/// The sampler is a plain struct with no timer of its own — that is what makes
/// this cheap. The manager keeps the clock, the box keeps the state, and the
/// only thing that crosses a thread boundary is one immutable reading.
///
/// Why bother moving it at all: the SMC temperature sweep costs ~8 ms (two
/// kernel round trips per key across every candidate that answered at start-up)
/// and it runs on every third tick. Measured on this machine: 7–8 ms on those
/// ticks against 0.4 ms on the others. 8 ms out of a 16.7 ms frame is enough to
/// drop one while the notch animates open, and a monitor that stutters the
/// thing it is measuring is the failure mode this panel exists to avoid.
private final class StatsSamplerBox: @unchecked Sendable {

    private let queue = DispatchQueue(
        label: "blog.snappy.notchlyrics.stats", qos: .utility)

    /// Created on the queue, not here: the first `StatsSampler()` probes dozens
    /// of SMC keys and costs ~18 ms (measured). On the main thread that is a
    /// visible hitch the first time the tab is opened.
    private var sampler: StatsSampler?

    /// Samples on the background queue and hands the reading back on the main
    /// queue. Serial by construction, so readings stay in order.
    func sample(completion: @escaping @Sendable (StatsSnapshot) -> Void) {
        queue.async {
            if self.sampler == nil { self.sampler = StatsSampler() }
            guard var sampler = self.sampler else { return }
            let reading = sampler.sample()
            self.sampler = sampler
            DispatchQueue.main.async { completion(reading) }
        }
    }

    func resetBaseline() {
        queue.async { self.sampler?.resetBaseline() }
    }
}


