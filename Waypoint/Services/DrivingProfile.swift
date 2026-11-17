import MapKit

struct DrivingRoad {
    var points: [MKMapPoint]
    var limits: [Double]
    var knownLimitCoverage: Double = 0

    private struct Trace: Decodable {
        struct Edge: Decodable {
            let speed_limit: Double?
            let begin_shape_index: Int
            let end_shape_index: Int
        }
        let shape: String
        let edges: [Edge]
    }

    static func load(_ line: MKPolyline) async -> DrivingRoad {
        let original = Array(UnsafeBufferPointer(start: line.points(), count: line.pointCount))
        let fallback = DrivingRoad(points: original, limits: Array(repeating: 40, count: max(0, original.count - 1)))
        guard original.count > 1,
              let url = URL(string: "https://valhalla1.openstreetmap.de/trace_attributes") else { return fallback }
        let stride = max(1, Int(ceil(Double(original.count) / 400)))
        let shape = original.enumerated().compactMap { index, point -> [String: Double]? in
            guard index.isMultiple(of: stride) || index == original.count - 1 else { return nil }
            return ["lat": point.coordinate.latitude, "lon": point.coordinate.longitude]
        }
        do {
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "shape": shape, "costing": "auto", "shape_match": "map_snap",
                "filters": ["action": "include", "attributes": ["shape", "edge.speed_limit", "edge.begin_shape_index", "edge.end_shape_index"]]
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return fallback }
            let trace = try JSONDecoder().decode(Trace.self, from: data)
            let points = decode(trace.shape)
            guard points.count > 1, points[0].distance(to: original[0]) < 100,
                  points[points.count - 1].distance(to: original[original.count - 1]) < 100
            else { return fallback }
            let matched = zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
            let expected = zip(original, original.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
            guard expected > 0, abs(matched - expected) / expected < 0.15 else { return fallback }
            var limits = Array(repeating: 40.0, count: points.count - 1)
            var known = Array(repeating: false, count: limits.count)
            for edge in trace.edges {
                guard let limit = edge.speed_limit, limit > 0, limit < 255,
                      edge.begin_shape_index >= 0, edge.end_shape_index <= limits.count,
                      edge.begin_shape_index < edge.end_shape_index else { continue }
                for index in edge.begin_shape_index..<edge.end_shape_index { limits[index] = limit; known[index] = true }
            }
            let covered = known.indices.reduce(0.0) { total, index in
                total + (known[index] ? points[index].distance(to: points[index + 1]) : 0)
            }
            return DrivingRoad(points: points, limits: limits, knownLimitCoverage: matched > 0 ? covered / matched : 0)
        } catch { return fallback }
    }

    private static func decode(_ shape: String) -> [MKMapPoint] {
        var lat = 0, lon = 0, value = 0, shift = 0
        var latitudeNext = true
        var points: [MKMapPoint] = []
        for byte in shape.utf8 {
            guard byte >= 63, byte <= 126, shift <= 30 else { return [] }
            let chunk = Int(byte) - 63
            value |= (chunk & 31) << shift
            if chunk >= 32 { shift += 5; continue }
            let delta = value & 1 == 0 ? value >> 1 : ~(value >> 1)
            if latitudeNext { lat += delta } else {
                lon += delta
                let point = CLLocationCoordinate2D(latitude: Double(lat) / 1e6, longitude: Double(lon) / 1e6)
                guard CLLocationCoordinate2DIsValid(point) else { return [] }
                points.append(MKMapPoint(point))
            }
            latitudeNext.toggle()
            shift = 0
            value = 0
        }
        return latitudeNext && shift == 0 ? points : []
    }

    func profile(offset: Double, reversed: Bool) -> DrivingProfile {
        let path = reversed ? Array(points.reversed()) : points
        let caps = (reversed ? Array(limits.reversed()) : limits).map { ($0 + offset) / 3.6 }
        return DrivingProfile(points: path, caps: caps, offset: offset)
    }
}

struct DrivingProfile {
    struct Leg {
        let start: MKMapPoint
        let end: MKMapPoint
        let distance: Double
        let baselineLimit: Double
        let initial: Double
        let peak: Double
        let final: Double
        let accelerate: Double
        let cruise: Double
        let brake: Double
        var duration: Double { accelerate + cruise + brake }
    }

    private let legs: [Leg]
    let duration: Double

    init(points: [MKMapPoint], caps: [Double], offset: Double) {
        // Sample long straight edges so a small cruising variation changes both pace and position.
        var sampled = [points[0]]
        var segmentCaps: [Double] = []
        var baselineLimits: [Double] = []
        var corners: [(index: Int, speed: Double)] = []
        var distanceAlong = 0.0
        for i in caps.indices {
            let start = points[i], end = points[i + 1]
            let length = start.distance(to: end)
            if length > 0 {
                let pieces = max(1, Int(ceil(length / 35)))
                for piece in 1...pieces {
                    let ratio = Double(piece) / Double(pieces)
                    let midpoint = distanceAlong + (Double(piece) - 0.5) * length / Double(pieces)
                    let variation = 1.5 * (1 + sin(midpoint / 28)) / 3.6
                    baselineLimits.append(caps[i] * 3.6 - offset)
                    segmentCaps.append(max(1, caps[i] - variation))
                    sampled.append(MKMapPoint(x: start.x + (end.x - start.x) * ratio,
                                              y: start.y + (end.y - start.y) * ratio))
                }
                distanceAlong += length
            }
            if i + 2 < points.count, length >= 3, end.distance(to: points[i + 2]) >= 3 {
                let next = points[i + 2]
                let before = atan2(end.y - start.y, end.x - start.x)
                let after = atan2(next.y - end.y, next.x - end.x)
                let angle = abs(atan2(sin(after - before), cos(after - before)))
                if angle > .pi / 6 {
                    let turnSpeed = max(12, 48 - angle * 17) / 3.6
                    corners.append((sampled.count - 1, turnSpeed))
                }
            }
        }
        let points = sampled
        let caps = segmentCaps
        let lengths = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
        var speeds = [0.0] + zip(caps, caps.dropFirst()).map { min($0, $1) } + [0]
        for corner in corners {
            speeds[corner.index] = min(speeds[corner.index], corner.speed)
        }
        for i in lengths.indices { speeds[i + 1] = min(speeds[i + 1], sqrt(pow(speeds[i], 2) + 3 * lengths[i])) }
        for i in lengths.indices.reversed() { speeds[i] = min(speeds[i], sqrt(pow(speeds[i + 1], 2) + 4 * lengths[i])) }
        legs = lengths.indices.compactMap { i in
            let distance = lengths[i], initial = speeds[i], final = speeds[i + 1]
            guard distance > 0 else { return nil }
            let peak = min(caps[i], sqrt((distance + initial * initial / 3 + final * final / 4) / (1.0 / 3 + 1.0 / 4)))
            let accelerate = max(0, (peak - initial) / 1.5)
            let brake = max(0, (peak - final) / 2)
            let cruise = max(0, distance - accelerate * (initial + peak) / 2 - brake * (peak + final) / 2) / peak
            return Leg(start: points[i], end: points[i + 1], distance: distance, baselineLimit: baselineLimits[i], initial: initial, peak: peak, final: final, accelerate: accelerate, cruise: cruise, brake: brake)
        }
        duration = legs.reduce(0) { $0 + $1.duration }
    }

    func position(at seconds: Double) -> (CLLocationCoordinate2D, Double, Double)? {
        var time = max(0, seconds)
        for leg in legs {
            if time >= leg.duration { time -= leg.duration; continue }
            let speed: Double
            let distance: Double
            if time < leg.accelerate {
                speed = leg.initial + 1.5 * time
                distance = time * (leg.initial + speed) / 2
            } else {
                let afterAcceleration = time - leg.accelerate
                let brakingTime = max(0, afterAcceleration - leg.cruise)
                speed = max(leg.final, leg.peak - 2 * brakingTime)
                distance = leg.accelerate * (leg.initial + leg.peak) / 2
                    + min(afterAcceleration, leg.cruise) * leg.peak + brakingTime * (leg.peak + speed) / 2
            }
            let ratio = min(1, distance / leg.distance)
            return (MKMapPoint(x: leg.start.x + ratio * (leg.end.x - leg.start.x),
                               y: leg.start.y + ratio * (leg.end.y - leg.start.y)).coordinate, speed * 3.6, leg.baselineLimit)
        }
        return legs.last.map { ($0.end.coordinate, 0, $0.baselineLimit) }
    }
}
