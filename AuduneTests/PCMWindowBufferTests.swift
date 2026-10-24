import XCTest
@testable import Audune

final class PCMWindowBufferTests: XCTestCase {
    func testPartialWindowIsNotPublished() {
        let buffer = PCMWindowBuffer()
        write(Array(repeating: 1, count: 1_000), to: buffer)

        XCTAssertEqual(buffer.allocatedSampleCount, PCMWindowBuffer.capacity)
        XCTAssertNil(buffer.copyLatestWindow())
    }

    func testLatestFullWindowIsReadable() {
        let buffer = PCMWindowBuffer()
        let samples = (0..<PCMWindowBuffer.windowLength).map { Float($0) }
        write(samples, to: buffer)

        let latest = buffer.copyLatestWindow()
        XCTAssertEqual(latest?.count, PCMWindowBuffer.windowLength)
        XCTAssertEqual(latest?.first, 0)
        XCTAssertEqual(latest?.last, Float(PCMWindowBuffer.windowLength - 1))
    }

    func testOverflowDropsOlderWindowsWithoutGrowing() {
        let buffer = PCMWindowBuffer()
        let samples = (0..<10_000).map { Float($0) }
        write(samples, to: buffer)

        XCTAssertEqual(buffer.allocatedSampleCount, 4_096)
        XCTAssertEqual(PCMWindowBuffer.capacity, 4_096)
        let latest = buffer.copyLatestWindow()
        XCTAssertEqual(latest?.count, 1_024)
        XCTAssertEqual(latest?.first, 8_192)
        XCTAssertEqual(latest?.last, 9_215)
    }

    private func write(_ samples: [Float], to buffer: PCMWindowBuffer) {
        samples.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            buffer.write(base, count: samples.count)
        }
    }
}
