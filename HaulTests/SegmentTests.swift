import Foundation
import Testing
@testable import Haul

struct SegmentTests {
    @Test func splitsIntoContiguousRanges() {
        let size: Int64 = 10 * 1024 * 1024
        let segments = Segment.split(size: size, connections: 4, resumable: true)
        #expect(segments.count == 4)
        #expect(segments.first?.start == 0)
        #expect(segments.last?.end == size - 1)
        for (a, b) in zip(segments, segments.dropFirst()) {
            #expect(a.end.map { $0 + 1 } == b.start)
        }
        #expect(segments.compactMap(\.length).reduce(0, +) == size)
    }

    @Test func smallFilesStayInOnePiece() {
        // Each segment is kept at 256 KB or more.
        #expect(Segment.split(size: 300 * 1024, connections: 8, resumable: true).count == 1)
        #expect(Segment.split(size: 1024 * 1024, connections: 8, resumable: true).count == 4)
    }

    @Test func nonResumableUsesOneConnection() {
        #expect(Segment.split(size: 100 * 1024 * 1024, connections: 8, resumable: false).count == 1)
    }

    @Test func unknownSizeStreamsToTheEnd() {
        let segments = Segment.split(size: nil, connections: 8, resumable: true)
        #expect(segments.count == 1)
        #expect(segments[0].end == nil)
        #expect(!segments[0].isComplete)
    }

    @Test func splitsTheRunningSegmentWithMostLeft() {
        var segments = [
            Segment(start: 0, end: 99, done: 100),
            Segment(start: 100, end: 199, done: 90),
            Segment(start: 200, end: 299, done: 20),
        ]
        let added = Segment.splitLargest(&segments, running: [1, 2], minimum: 10)
        #expect(added == 3)
        // 80 bytes left from 220: the running connection keeps 220–259, the new segment takes 260–299.
        #expect(segments[2].end == 259)
        #expect(segments[3] == Segment(start: 260, end: 299))
        #expect(segments.compactMap(\.length).reduce(0, +) == 300)
    }

    @Test func leavesSmallOrUnboundedSegmentsAlone() {
        var segments = [Segment(start: 0, end: 99, done: 85), Segment(start: 100, end: nil, done: 50)]
        #expect(Segment.splitLargest(&segments, running: [0, 1], minimum: 10) == nil)
        #expect(segments.count == 2)
        #expect(segments[0].end == 99)
    }

    @Test(arguments: [Int64(300 * 1024), 1024 * 1024, 100 * 1024 * 1024, -1], [true, false])
    func connectionsMatchTheSegmentsSplitInto(_ size: Int64, _ resumable: Bool) {
        let size = size < 0 ? nil : size
        let connections = Segment.connections(size: size, requested: 8, resumable: resumable)
        #expect(connections == Segment.split(size: size, connections: 8, resumable: resumable).count)
    }

    @Test func completionAndFraction() {
        var s = Segment(start: 100, end: 199)
        #expect(s.length == 100)
        s.done = 25
        #expect(s.fraction == 0.25)
        #expect(!s.isComplete)
        s.done = 100
        #expect(s.isComplete)
    }
}

struct DownloadModelTests {
    private func download(size: Int64?, done: Int64, status: DownloadStatus = .downloading) -> Download {
        var d = Download(url: URL(string: "https://example.com/file.zip")!, name: "file.zip", size: size, status: status, connections: 1)
        d.segments = [Segment(start: 0, end: size.map { $0 - 1 }, done: done)]
        return d
    }

    @Test func progress() {
        #expect(download(size: 200, done: 50).progress == 0.25)
        #expect(download(size: nil, done: 50).progress == 0)
        #expect(download(size: 200, done: 0, status: .completed).progress == 1)
    }

    @Test func remainingTime() {
        var d = download(size: 1000, done: 400)
        #expect(d.remainingTime == nil)
        d.speed = 100
        #expect(d.remainingTime == 6)
    }
}
