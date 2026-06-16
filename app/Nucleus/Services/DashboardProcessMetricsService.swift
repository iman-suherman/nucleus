import Darwin
import Foundation

struct DashboardProcessMetrics: Equatable {
    var cpuUsagePercent: Double
    var memoryFootprintBytes: UInt64

    var formattedCPU: String {
        DashboardProcessMetricsFormatting.formatCPU(cpuUsagePercent)
    }

    var formattedMemory: String {
        DashboardProcessMetricsFormatting.formatMemory(memoryFootprintBytes)
    }
}

enum DashboardProcessMetricsFormatting {
    static func formatCPU(_ percent: Double) -> String {
        if percent < 10 {
            return String(format: "%.1f%%", percent)
        }
        return String(format: "%.0f%%", percent.rounded())
    }

    static func formatMemory(_ bytes: UInt64) -> String {
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
final class DashboardProcessMetricsService: ObservableObject {
    static let shared = DashboardProcessMetricsService()

    @Published private(set) var metrics: DashboardProcessMetrics?

    private var samplingTask: Task<Void, Never>?
    private var previousCPUTimeNanoseconds: UInt64?
    private var previousSampleDate: Date?

    private init() {}

    func startSamplingIfNeeded() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopSampling() {
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
}
