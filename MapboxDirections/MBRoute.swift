import Polyline

/**
 A `Route` object defines a single route that the user can follow to visit a series of waypoints in order. The route object includes information about the route, such as its distance and expected travel time. Depending on the criteria used to calculate the route, the route object may also include detailed turn-by-turn instructions.
 
 Typically, you do not create instances of this class directly. Instead, you receive route objects when you request directions using the `Directions.calculate(_:completionHandler:)` method. However, if you use the `Directions.url(forCalculating:)` method instead, you can pass the results of the HTTP request into this class’s initializer.
 */
@objc(MBRoute)
open class Route: DirectionRoute {
    // MARK: Creating a Route
    
    @objc internal init(routeOptions: RouteOptions, legs: [RouteLeg], distance: CLLocationDistance, expectedTravelTime: TimeInterval, coordinates: [CLLocationCoordinate2D]?, speechLocale: Locale?) {
        super.init(directionOptions: routeOptions, legs: legs, distance: distance, expectedTravelTime: expectedTravelTime, coordinates: coordinates, speechLocale: speechLocale)
    }
    
    /**
     Initializes a new route object with the given JSON dictionary representation and waypoints.
     
     This initializer is intended for use in conjunction with the `Directions.url(forCalculating:)` method.
     
     - parameter json: A JSON dictionary representation of the route as returned by the Mapbox Directions API.
     - parameter waypoints: An array of waypoints that the route visits in chronological order.
     - parameter routeOptions: The `RouteOptions` used to create the request.
     */
    @objc public init(json: [String: Any], waypoints: [Waypoint], routeOptions: RouteOptions) {
        // Associate each leg JSON with a source and destination. The sequence of destinations is offset by one from the sequence of sources.
        let legInfo = zip(zip(waypoints.prefix(upTo: waypoints.endIndex - 1), waypoints.suffix(from: 1)),
                          json["legs"] as? [JSONDictionary] ?? [])
        let legs = legInfo.map { (endpoints, json) -> RouteLeg in
            RouteLeg(json: json, source: endpoints.0, destination: endpoints.1, profileIdentifier: routeOptions.profileIdentifier)
        }
        let distance = json["distance"] as! Double
        let expectedTravelTime = json["duration"] as! Double
        
        var coordinates: [CLLocationCoordinate2D]?
        switch json["geometry"] {
        case let geometry as JSONDictionary:
            coordinates = CLLocationCoordinate2D.coordinates(geoJSON: geometry)
        case let geometry as String:
            coordinates = decodePolyline(geometry, precision: 1e5)!
        default:
            coordinates = nil
        }
        
        var speechLocale: Locale?
        if let locale = json["voiceLocale"] as? String {
            speechLocale = Locale(identifier: locale)
        }
        
        super.init(directionOptions: routeOptions, legs: legs, distance: distance, expectedTravelTime: expectedTravelTime, coordinates: coordinates, speechLocale: speechLocale)
    }
    
    @objc public required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
    }
}

// MARK: Support for Directions API v4

internal class RouteV4: Route {
    convenience override init(json: JSONDictionary, waypoints: [Waypoint], routeOptions: RouteOptions) {
        let leg = RouteLegV4(json: json, source: waypoints.first!, destination: waypoints.last!, profileIdentifier: routeOptions.profileIdentifier)
        let distance = json["distance"] as! Double
        let expectedTravelTime = json["duration"] as! Double
        
        var coordinates: [CLLocationCoordinate2D]?
        switch json["geometry"] {
        case let geometry as JSONDictionary:
            coordinates = CLLocationCoordinate2D.coordinates(geoJSON: geometry)
        case let geometry as String:
            coordinates = decodePolyline(geometry, precision: 1e6)!
        default:
            coordinates = nil
        }
        
        self.init(routeOptions: routeOptions, legs: [leg], distance: distance, expectedTravelTime: expectedTravelTime, coordinates: coordinates, speechLocale: nil)
    }
}
