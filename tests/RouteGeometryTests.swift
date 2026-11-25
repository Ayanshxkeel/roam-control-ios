import MapKit

@main struct RouteGeometryTests {
    static func main() {
        let p = [MKMapPoint(x: 134000000, y: 94000000), MKMapPoint(x: 134010000, y: 94000000), MKMapPoint(x: 134010000, y: 94010000)]
        let line = MKPolyline(points: p, count: p.count)
        let midway = MKMapPoint(x: 134005000, y: 94000200).coordinate
        let covered = RouteGeometry.covered(line, to: midway)!
        precondition(covered.pointCount == 2)
        precondition(abs(covered.points()[1].x - 134005000) < 0.01)
        precondition(abs(covered.points()[1].y - 94000000) < 0.01, "Green endpoint must project onto the road")
        let reverse = Array(p.reversed())
        let back = RouteGeometry.covered(MKPolyline(points: reverse, count: reverse.count), to: midway)!
        precondition(back.pointCount == 3, "Return route should cover the opposite prefix")
        let end = RouteGeometry.covered(line, to: p[2].coordinate)!
        precondition(abs(end.points()[end.pointCount - 1].y - p[2].y) < 0.01)
        precondition(RouteGeometry.covered(MKPolyline(points: [p[0]], count: 1), to: midway) == nil)
        print("PASS: travelled-road projection, return route, arrival and empty geometry")
    }
}
