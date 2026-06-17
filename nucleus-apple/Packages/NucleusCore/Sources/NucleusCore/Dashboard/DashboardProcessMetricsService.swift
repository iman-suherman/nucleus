import Darwin
import Foundation

public struct DashboardProcessMetrics: Equatable, Sendable {
    public var cpuUsagePercent: Double
    public var memoryFootprintBytes: UInt64

    public var formattedCPU: String {
        DashboardProcessMetricsFormatting.formatCPU(cpuUsagePercent)
    }

    public var formattedMemory: String {
        DashboardProcessMetricsFormatting.formatMemory(memoryFootprintBytes)
    }

    public init(cpuUsagePercent: Double, memoryFootprintBytes: UInt64) {
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryFootprintBytes = memoryFootprintBytes
    }
}

public enum DashboardProcessMetricsFormatting {
    public static func formatCPU(_ percent: Double) -> String {
        if percent < 10 {
            return String(format: "%.1f%%", percent)
        }
        return String(format: "%.0f%%", percent.rounded())
    }

    public static func formatMemory(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes >= 1024 {
            return String(format: "%.1f GB", megabytes / 1024)
        }
        if megabytes >= 100 {
            return String(format: "%.0f MB", megabytes.rounded())
        }
        return String(format: "%.1f MB", megabytes)
    }
}

@MainActor
public final class DashboardProcessMetricsService: ObservableObject {
    public static let shared = DashboardProcessMetricsService()

    @Published public private(set) var metrics: DashboardProcessMetrics?

    private var samplingTask: Task<Void, Never>?
    private var previousCPUTimeNanoseconds: UInt64?
    private var previousSampleDate: Date?

    private init() {}

    public func startSamplingIfNeeded() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    public func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    private func sample() {
        guard let memoryFootprintBytes = Self.memoryFootprintBytes() else { return }

        let now = Date()
        let cpuUsagePercent = Self.cpuUsagePercent(
            now: now,
            previousCPUTimeNanoseconds: &previousCPUTimeNanoseconds,
            previousSampleDate: &previousSampleDate
        )

        metrics = DashboardProcessMetrics(
            cpuUsagePercent: cpuUsagePercent,
            memoryFootprintBytes: memoryFootprintBytes
        )
    }

    private static func memoryFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    private static func cpuUsagePercent(
        now: Date,
        previousCPUTimeNanoseconds: inout UInt64?,
        previousSampleDate: inout Date?
    ) -> Double {
        #if os(macOS)
        return macCPUUsagePercent(
            now: now,
            previousCPUTimeNanoseconds: &previousCPUTimeNanoseconds,
            previousSampleDate: &previousSampleDate
        )
        #else
        return iosCPUUsagePercent()
        #endif
    }

    #if os(macOS)
    private static func macCPUUsagePercent(
        now: Date,
        previousCPUTimeNanoseconds: inout UInt64?,
        previousSampleDate: inout Date?
    ) -> Double {
        var info = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let result = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, Int32(size))
        guard result == Int32(size) else { return 0 }

        let totalCPUTime = info.pti_total_user + info.pti_total_system

        defer {
            previousCPUTimeNanoseconds = totalCPUTime
            previousSampleDate = now
        }

        guard
            let previousCPUTime = previousCPUTimeNanoseconds,
            let previousDate = previousSampleDate,
            totalCPUTime >= previousCPUTime
        else {
            return 0
        }

        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0 else { return 0 }

        let cpuDelta = Double(totalCPUTime - previousCPUTime)
        let processorCount = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let usage = (cpuDelta / (elapsed * 1_000_000_000)) / Double(processorCount) * 100
        return min(max(usage, 0), 100)
    }
    #endif

    #if os(iOS)
    private static func iosCPUUsagePercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threadList else {
            return 0
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: threadList)),
                vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size)
            )
        }

        var totalUsage = 0.0
        for index in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(THREAD_INFO_MAX)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threadList[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { continue }
            if info.flags != TH_FLAGS_IDLE {
                totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }

        return min(max(totalUsage, 0), 100)
    }
    #endif
}
