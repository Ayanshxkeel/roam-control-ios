import MapKit

enum RouteGeometry {
    /// Project the current location onto the nearest segment of the displayed route.
    static func covered(_ line: MKPolyline, to coordinate: CLLocationCoordinate2D) -> MKPolyline? {
        guard line.pointCount > 1 else { return nil }
        let target = MKMapPoint(coordinate)
        let points = line.points()
        var best = Double.infinity, endIndex = 0
        var endpoint = points[0]
        for i in 0..<(line.pointCount - 1) {
            let a = points[i], b = points[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
            let t = length > 0 ? min(1, max(0, ((target.x - a.x) * dx + (target.y - a.y) * dy) / length)) : 0
            let projected = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
            let distance = (target.x - projected.x) * (target.x - projected.x) + (target.y - projected.y) * (target.y - projected.y)
            if distance < best { best = distance; endIndex = i; endpoint = projected }
        }
        var covered = (0...endIndex).map { points[$0].coordinate }
        covered.append(endpoint.coordinate)
        return MKPolyline(coordinates: covered, count: covered.count)
    }
}
