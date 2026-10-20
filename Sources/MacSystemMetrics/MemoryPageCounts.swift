import MacStatusCore

struct MemoryPageCounts: Sendable {
    let anonymous: UInt64
    let purgeable: UInt64
    let wired: UInt64
    let compressed: UInt64

    func usedBytes(pageSize: UInt64, totalBytes: UInt64) throws(MemoryReadError) -> UInt64 {
        guard pageSize > 0, totalBytes > 0 else {
            throw .invalidStatistics
        }

        // File-backed cache is excluded. Count compressor storage, not the
        // uncompressed size of the pages it represents.
        let (application, subtractionOverflow) = anonymous.subtractingReportingOverflow(purgeable)
        let (resident, residentOverflow) = application.addingReportingOverflow(wired)
        let (usedPages, pagesOverflow) = resident.addingReportingOverflow(compressed)
        let (bytes, bytesOverflow) = usedPages.multipliedReportingOverflow(by: pageSize)
        guard !subtractionOverflow, !residentOverflow, !pagesOverflow, !bytesOverflow,
              bytes <= totalBytes else {
            throw .invalidStatistics
        }
        return bytes
    }
}
