func calculerDureeTotaleSegmentsActifs(segments: [TranscriptionSegment]) -> TimeInterval {
    return segments
        .filter { $0.isActive }
        .reduce(0.0) { total, segment in
            return total + (segment.endTime - segment.startTime)
        }
} 