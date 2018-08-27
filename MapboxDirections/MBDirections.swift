
typealias JSONDictionary = [String: Any]

/// Indicates that an error occurred in MapboxDirections.
public let MBDirectionsErrorDomain = "MBDirectionsErrorDomain"

/// The Mapbox access token specified in the main application bundle’s Info.plist.
let defaultAccessToken = Bundle.main.object(forInfoDictionaryKey: "MGLMapboxAccessToken") as? String

var globalOSRMPath: String?
var globalOptions: RouteOptions?


/// The user agent string for any HTTP requests performed directly within this library.
let userAgent: String = {
    var components: [String] = []

    if let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        components.append("\(appName)/\(version)")
    }

    let libraryBundle: Bundle? = Bundle(for: Directions.self)

    if let libraryName = libraryBundle?.infoDictionary?["CFBundleName"] as? String, let version = libraryBundle?.infoDictionary?["CFBundleShortVersionString"] as? String {
        components.append("\(libraryName)/\(version)")
    }

    let system: String
    #if os(OSX)
        system = "macOS"
    #elseif os(iOS)
        system = "iOS"
    #elseif os(watchOS)
        system = "watchOS"
    #elseif os(tvOS)
        system = "tvOS"
    #elseif os(Linux)
        system = "Linux"
    #endif
    let systemVersion = ProcessInfo().operatingSystemVersion
    components.append("\(system)/\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)")

    let chip: String
    #if arch(x86_64)
        chip = "x86_64"
    #elseif arch(arm)
        chip = "arm"
    #elseif arch(arm64)
        chip = "arm64"
    #elseif arch(i386)
        chip = "i386"
    #endif
    components.append("(\(chip))")

    return components.joined(separator: " ")
}()

extension CLLocationCoordinate2D {
    /**
     Initializes a coordinate pair based on the given GeoJSON coordinates array.
     */
    internal init(geoJSON array: [Double]) {
        assert(array.count == 2)
        self.init(latitude: array[1], longitude: array[0])
    }

    /**
     Initializes a coordinate pair based on the given GeoJSON point object.
     */
    internal init(geoJSON point: JSONDictionary) {
        assert(point["type"] as? String == "Point")
        self.init(geoJSON: point["coordinates"] as! [Double])
    }

    internal static func coordinates(geoJSON lineString: JSONDictionary) -> [CLLocationCoordinate2D] {
        let type = lineString["type"] as? String
        assert(type == "LineString" || type == "Point")
        let coordinates = lineString["coordinates"] as! [[Double]]
        return coordinates.map { self.init(geoJSON: $0) }
    }
}

extension CLLocation {
    /**
     Initializes a CLLocation object with the given coordinate pair.
     */
    internal convenience init(coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

/**
 A `Directions` object provides you with optimal directions between different locations, or waypoints. The directions object passes your request to the [Mapbox Directions API](https://www.mapbox.com/api-documentation/?language=Swift#directions) and returns the requested information to a closure (block) that you provide. A directions object can handle multiple simultaneous requests. A `RouteOptions` object specifies criteria for the results, such as intermediate waypoints, a mode of transportation, or the level of detail to be returned.

 Each result produced by the directions object is stored in a `Route` object. Depending on the `RouteOptions` object you provide, each route may include detailed information suitable for turn-by-turn directions, or it may include only high-level information such as the distance, estimated travel time, and name of each leg of the trip. The waypoints that form the request may be conflated with nearby locations, as appropriate; the resulting waypoints are provided to the closure.
 */
@objc(MBDirections)
open class Directions: NSObject {
    /**
     A closure (block) to be called when a directions request is complete.

     - parameter waypoints: An array of `Waypoint` objects. Each waypoint object corresponds to a `Waypoint` object in the original `RouteOptions` object. The locations and names of these waypoints are the result of conflating the original waypoints to known roads. The waypoints may include additional information that was not specified in the original waypoints.

        If the request was canceled or there was an error obtaining the routes, this parameter may be `nil`.
     - parameter routes: An array of `Route` objects. The preferred route is first; any alternative routes come next if the `RouteOptions` object’s `includesAlternativeRoutes` property was set to `true`. The preferred route depends on the route options object’s `profileIdentifier` property.

        If the request was canceled or there was an error obtaining the routes, this parameter is `nil`. This is not to be confused with the situation in which no results were found, in which case the array is present but empty.
     - parameter error: The error that occurred, or `nil` if the placemarks were obtained successfully.
     */
    public typealias RouteCompletionHandler = (_ waypoints: [Waypoint]?, _ routes: [Route]?, _ error: NSError?) -> Void

    /**
     A closure (block) to be called when a map matching request is complete.

     If the request was canceled or there was an error obtaining the matches, this parameter is `nil`. This is not to be confused with the situation in which no matches were found, in which case the array is present but empty.
     - parameter error: The error that occurred, or `nil` if the placemarks were obtained successfully.
     */
    public typealias MatchCompletionHandler = (_ matches: [Match]?, _ error: NSError?) -> Void

    // MARK: Creating a Directions Object

    /**
     The shared directions object.

     To use this object, a Mapbox [access token](https://www.mapbox.com/help/define-access-token/) should be specified in the `MGLMapboxAccessToken` key in the main application bundle’s Info.plist.
     */
    @objc(sharedDirections)
    open static let shared = Directions(accessToken: nil)

    /// The API endpoint to request the directions from.
    internal var apiEndpoint: URL

    /// The Mapbox access token to associate the request with.
    internal let accessToken: String

    /**
     Initializes a newly created directions object with an optional access token and host.

     - parameter accessToken: A Mapbox [access token](https://www.mapbox.com/help/define-access-token/). If an access token is not specified when initializing the directions object, it should be specified in the `MGLMapboxAccessToken` key in the main application bundle’s Info.plist.
     - parameter host: An optional hostname to the server API. The [Mapbox Directions API](https://www.mapbox.com/api-documentation/?language=Swift#directions) endpoint is used by default.
     */
    @objc public init(accessToken: String?, host: String?) {
        let accessToken = accessToken ?? defaultAccessToken
        assert(accessToken != nil && !accessToken!.isEmpty, "A Mapbox access token is required. Go to <https://www.mapbox.com/studio/account/tokens/>. In Info.plist, set the MGLMapboxAccessToken key to your access token, or use the Directions(accessToken:host:) initializer.")

        self.accessToken = accessToken!

        var baseURLComponents = URLComponents()
        baseURLComponents.scheme = "https"
        baseURLComponents.host = host ?? "api.mapbox.com"
        self.apiEndpoint = baseURLComponents.url!
    }

    /**
     Initializes a newly created directions object with an optional access token.

     The directions object sends requests to the [Mapbox Directions API](https://www.mapbox.com/api-documentation/?language=Swift#directions) endpoint.

     - parameter accessToken: A Mapbox [access token](https://www.mapbox.com/help/define-access-token/). If an access token is not specified when initializing the directions object, it should be specified in the `MGLMapboxAccessToken` key in the main application bundle’s Info.plist.
     */
    @objc public convenience init(accessToken: String?) {
        self.init(accessToken: accessToken, host: nil)
    }

    // MARK: Getting Directions

    /**
     - (void)getJSON:(CLLocationCoordinate2D *)start end:(CLLocationCoordinate2D *)end xmlpath:(NSString *)xmlpath{

     NSString* sourcePath = [[NSBundle mainBundle] pathForResource:@"billings2" ofType:@"xml"];
     //    NSString* sourcePath = [[NSBundle mainBundle] pathForResource:@"billings2" inDirectory:@"billings" ofType:@"xml"];


     //    NSString *documentDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];

     //    NSString *documentPath = [NSString stringWithFormat:@"%@/%@%s", documentDir, xmlpath, ".osrm"];
     NSString *documentPath = [NSString stringWithFormat:@"%@%s", sourcePath, ".osrm"];

     //    NSLog(@"PATH: %@", sourcePath);

     RouteService *routeService = [[RouteService alloc] initWithMapData: documentPath];

     routeService.overview = ORSMOverviewFull;

     routeService.geometries = ORSMGeometryGeoJSON;
     routeService.steps = true;
     NSDictionary<NSString *, NSObject *> *jsonResult;


     jsonResult = [routeService getRoutesFrom:*start to:*end];
     NSLog(@"%@", jsonResult);

     NSMutableArray *newroutes = [[NSMutableArray alloc] init];
     for (NSObject *route in [jsonResult valueForKeyPath:@"routes"]) {
     [route setValue:@"en-US" forKey:@"voiceLocale"];
     NSMutableArray *newlegs = [[NSMutableArray alloc] init];
     for (NSObject *leg in [route valueForKey:@"legs"]){
     //            [routeMessage appendFormat:@"Route via %@:\n\n", leg];
     //            [self setCurrentMessage: routeMessage];
     //            NSLengthFormatter *distanceFormatter = [[NSLengthFormatter alloc] init];
     //            NSString *formattedDistance = [distanceFormatter stringFromMeters: leg.distance];

     //            NSDateComponentsFormatter *travelTimeFormatter = [[NSDateComponentsFormatter alloc] init];

     //            travelTimeFormatter.unitsStyle = NSDateComponentsFormatterUnitsStyleShort;
     //            NSString *formattedTravelTime = [travelTimeFormatter stringFromTimeInterval: route.expectedTravelTime];
     //            NSLog(@"Distance: %@; ETA: %@", formattedDistance, formattedTravelTime);

     //            [routeMessage appendFormat:@"Distance: %@; ETA: %@\n\n", formattedDistance, formattedTravelTime];
     NSMutableArray *newsteps = [[NSMutableArray alloc] init];
     for (NSObject *step in [leg valueForKey:@"steps"]){
     NSMutableArray *voiceInstructions = [[NSMutableArray alloc] init];
     NSMutableDictionary *voiceObject = [[NSMutableDictionary alloc] init];

     OSRMInstructionFormatter *osrminstructionFormatter = [[OSRMInstructionFormatter alloc] initWithVersion:@"v5"];
     //                [distanceFormatter setUnitStyle:NSFormattingUnitStyleMedium];
     //                NSLog(@"%@", [osrminstructionFormatter stringForObjectValue:step]);
     //                [routeMessage appendFormat: @"%@\n\n", [osrminstructionFormatter stringForObjectValue:step]];
     //                NSString *formattedDistance = [distanceFormatter stringFromMeters:step.distance];
     //                NSLog(@"— %@ —", formattedDistance);
     //                [routeMessage appendFormat:@"— %@ —\n\n", formattedDistance];
     //            NSNumber *dis = [distanceFormatter doub]
     //                [step va]
     double distance = [[step valueForKey:@"distance"] doubleValue];
     NSNumber *dis = [[NSNumber alloc] initWithDouble:distance];
     NSMutableString *msg = [[NSMutableString alloc] init];
     [msg appendString:@"<speak><amazon:effect name=\"drc\"><prosody rate=\"1.08\">"];
     //                MBRouteStep *this_step = step;
     MBRouteStep *this_step = [[MBRouteStep alloc] initWithJson:step];
     [msg appendString:[osrminstructionFormatter stringForObjectValue:this_step]];
     [msg appendString:@"</prosody></amazon:effect></speak>"];
     //                            NSString *msg = [NSString stringWithFormat:@"%s/%@/%s", "<speak><amazon:effect name=\"drc\"><prosody rate=\"1.08\">", [osrminstructionFormatter stringForObjectValue:step], "</prosody></amazon:effect></speak>"];
     [voiceObject setObject:dis forKey:@"distanceAlongGeometry"];
     [voiceObject setObject:[osrminstructionFormatter stringForObjectValue:this_step] forKey:@"announcement"];
     [voiceObject setObject:msg forKey:@"ssmlAnnouncement"];
     [voiceInstructions addObject:voiceObject];
     [step setValue:voiceInstructions forKey:@"voiceInstructions"];
     //                [step setObject:voiceInstructions forKey:@"voiceInstructions"];
     [newsteps addObject:step];
     }
     [leg setValue:newsteps forKeyPath:@"steps" ];
     [newlegs addObject:leg];


     }
     [route setValue:newlegs forKeyPath:@"legs"];
     [newroutes addObject:route];
     }


     }
     */
//    @objc (getJSON:start)
    @discardableResult open func getJSONString (jsonResult: Dictionary<String, Any>) -> String{
//        NSError *error;
//        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonResult
//            options:NSJSONWritingPrettyPrinted error:&error];
//        NSString *jsonString = [[NSString alloc] initWithData:jsonData
//            encoding:NSUTF8StringEncoding];
//        NSLog(@"Response JSON=%@", jsonString);
//        var error = Error?()
//        var error = NSError(domain:"", code:httpResponse.statusCode, userInfo:nil)
//        if let jsonResult = jsonResult as? [String: Any] {
//            print(jsonResult["team1"])
//        }
        var JSONString = "{}"
        do{
            let jsonData = try JSONSerialization.data(withJSONObject: jsonResult, options: JSONSerialization.WritingOptions.prettyPrinted)
            let jsonString = String.init(data: jsonData, encoding: String.Encoding.utf8)
            JSONString = jsonString!
        }
        catch {
            print(error.localizedDescription)
        }
        return JSONString
        
//        var err: NSError?
//        let _:NSData! = JSONSerialization.dataWithJSONObject(jsonResult,
//                                                                    options:JSONSerialization.WritingOptions.PrettyPrinted)
        
        
    }
    
    @discardableResult open func getWaypoints(location: CLLocationCoordinate2D, osrmPath: String) -> Dictionary<String, Any>{
        let nearestService = NearestService.init(mapData: osrmPath)
        let jsonResult = nearestService?.getWaypointsFrom(location)
        return jsonResult!
    }
    
    @discardableResult open func getJSON(_ start: CLLocationCoordinate2D, end: CLLocationCoordinate2D, osrmPath: String) -> Dictionary<String, Any> {

        let routeService = RouteService.init(mapData: osrmPath)
        
        routeService?.overview = .full
        routeService?.geometries = .polyline
        routeService?.steps = true
        let jsonResult = routeService?.getRoutesFrom(start, to: end)
//        print(jsonResult)
        var newroutes = [Dictionary<String, Any>]()
//        let jsonData = try JSONSerialization.jsonObject(with: jsonResult, options: [])
//        do {
//            let jsonData = try JSONSerialization.data(withJSONObject: jsonResult ?? {}, options: .prettyPrinted)
//
//        }catch{
//            print(error.localizedDescription)
//        }
//        let newjsonResult = jsonResult as Dictionary
//        let routes = jsonResult.valueForKeyPath("routes")

        for r in jsonResult!["routes"] as! [Dictionary<String, Any>]{
            var route = r
            route["voiceLocal"] = "en-US"
            var newlegs = [Dictionary<String, Any>]()
            for leg in route["legs"] as! [Dictionary<String, Any>]{
                var newsteps = [Dictionary<String, Any>]()
                for step in leg["steps"] as! [Dictionary<String, Any>]{
                    var voiceInstructions = [Dictionary<String, Any>]()
                    var voiceObject = Dictionary<String, Any>()
                    var bannerInstructions = [Dictionary<String, Any>]()
                    var bannerObject = Dictionary<String, Any>()
                    var primary = Dictionary<String, Any>()
                    var components = [Dictionary<String, Any>]()
                    var component = Dictionary<String, Any>()
                    //                    let osrminstructionFormatter = OSRMInstructionFormatter.ini
                    let dis = step["distance"]
//                    OSRMInstructionFormatter *osrminstructionFormatter = [[OSRMInstructionFormatter alloc] initWithVersion:@"v5"];
                    let osrminstructionFormatter = OSRMInstructionFormatter.init(version: "v5")
//                    let osrminstructionFormatter = OSRMInstructionFormatter(initWithVersion: "v5")
//                    MBRouteStep *this_step = [[MBRouteStep alloc] initWithJson:step];
//                    [msg appendString:[osrminstructionFormatter stringForObjectValue:this_step]];
//                    let this_step = MBRouteStep.init(json: step, options: nil)
                    let this_step = RouteStep.init(json: step, options: globalOptions!)
//                    let instruction = osrminstructionFormatter(stringForObjectValue:this_step)
                    let instruction = osrminstructionFormatter.string(for: this_step)
//                    let maneuver = step["maneuver"] as! Dictionary<String, Any>
//                    let instruction = maneuver["instruction"] as! String
                    let msg = "<speak><amazon:effect name=\"drc\"><prosody rate=\"1.08\">" + instruction! + "</prosody></amazon:effect></speak>"
                    voiceObject["distanceAlongGeometry"] = dis
                    voiceObject["announcement"] = instruction
                    voiceObject["ssmlAnnouncement"] = msg
                    voiceInstructions.append(voiceObject)
//                    "bannerInstructions": [
//                    {
//                    "distanceAlongGeometry": 296,
//                    "primary": {
//                    "text": "Cardiff Road",
//                    "components": [
//                    {
//                    "text": "Cardiff Road",
//                    "type": "text",
//                    "abbr": "Cardiff Rd",
//                    "abbr_priority": 0
//                    }
//                    ],
//                    "type": "turn",
//                    "modifier": "left"
//                    },
//                    "secondary": null
//                    }
//                    ]
//                },
                    
                    var newstep = step
//                    newstep["driving_side"] = "right"
                    var maneuver = newstep["maneuver"] as! Dictionary<String, Any>
                    maneuver["instruction"] = instruction
                    component["text"] = step["name"]
                    component["type"] = "text"
                    component["abbr"] = step["name"]
                    component["abbr_priority"] = 0
                    components.append(component)
                    primary["text"] = step["name"]
                    primary["components"] = components
                    primary["type"] = maneuver["type"]
                    primary["modifier"] = maneuver["modifier"]
                    bannerObject["distanceAlongGeometry"] = dis
                    bannerObject["primary"] = primary
                    bannerObject["secondary"] = nil
                    bannerInstructions.append(bannerObject)
//                    maneuver["type"] = "depart"
                    newstep["maneuver"] = maneuver
                    newstep["bannerInstructions"] = bannerInstructions
                    newstep["voiceInstructions"] = voiceInstructions
                    newsteps.append(newstep)

                }
                var newleg = leg
                newleg["steps"] = newsteps
                newlegs.append(newleg)
            }
            route["legs"] = newlegs
            newroutes.append(route)
        }
        var newjsonResult = jsonResult
        newjsonResult!["routes"] = newroutes as NSObject
//        jsonResult["routes"] = newroutes

//        NSMutableArray *newroutes = [[NSMutableArray alloc] init];
//        for (NSObject *route in [jsonResult valueForKeyPath:@"routes"]) {
//            [route setValue:@"en-US" forKey:@"voiceLocale"];
//            NSMutableArray *newlegs = [[NSMutableArray alloc] init];
//            for (NSObject *leg in [route valueForKey:@"legs"]){
//
//                NSMutableArray *newsteps = [[NSMutableArray alloc] init];
//                for (NSObject *step in [leg valueForKey:@"steps"]){
//                    NSMutableArray *voiceInstructions = [[NSMutableArray alloc] init];
//                    NSMutableDictionary *voiceObject = [[NSMutableDictionary alloc] init];
//
//                    OSRMInstructionFormatter *osrminstructionFormatter = [[OSRMInstructionFormatter alloc] initWithVersion:@"v5"];
//
//                    double distance = [[step valueForKey:@"distance"] doubleValue];
//                    NSNumber *dis = [[NSNumber alloc] initWithDouble:distance];
//                    NSMutableString *msg = [[NSMutableString alloc] init];
//                    [msg appendString:@"<speak><amazon:effect name=\"drc\"><prosody rate=\"1.08\">"];
//
//                    MBRouteStep *this_step = [[MBRouteStep alloc] initWithJson:step];
//                    [msg appendString:[osrminstructionFormatter stringForObjectValue:this_step]];
//                    [msg appendString:@"</prosody></amazon:effect></speak>"];
//
//                    [voiceObject setObject:dis forKey:@"distanceAlongGeometry"];
//                    [voiceObject setObject:[osrminstructionFormatter stringForObjectValue:this_step] forKey:@"announcement"];
//                    [voiceObject setObject:msg forKey:@"ssmlAnnouncement"];
//                    [voiceInstructions addObject:voiceObject];
//                    [step setValue:voiceInstructions forKey:@"voiceInstructions"];
//
//                    [newsteps addObject:step];
//                }
//                [leg setValue:newsteps forKeyPath:@"steps" ];
//                [newlegs addObject:leg];
//
//
//            }
//            [route setValue:newlegs forKeyPath:@"legs"];
//            [newroutes addObject:route];
//        }
//        print(newjsonResult as Any)
        return newjsonResult!
    }
    /**
     Begins asynchronously calculating the route or routes using the given options and delivers the results to a closure.

     This method retrieves the routes asynchronously over a network connection. If a connection error or server error occurs, details about the error are passed into the given completion handler in lieu of the routes.

     Routes may be displayed atop a [Mapbox map](https://www.mapbox.com/maps/). They may be cached but may not be stored permanently. To use the results in other contexts or store them permanently, [upgrade to a Mapbox enterprise plan](https://www.mapbox.com/directions/#pricing).

     - parameter options: A `RouteOptions` object specifying the requirements for the resulting routes.
     - parameter completionHandler: The closure (block) to call with the resulting routes. This closure is executed on the application’s main thread.
     - returns: The data task used to perform the HTTP request. If, while waiting for the completion handler to execute, you no longer want the resulting routes, cancel this task.
     */
    @objc(calculateDirectionsWithOptions:osrmPath:completionHandler:)
    @discardableResult open func calculate(_ options: RouteOptions, osrmPath: String? = nil, completionHandler: @escaping RouteCompletionHandler) -> URLSessionDataTask {
        if globalOptions == nil{
            globalOptions = options
        }
        if globalOSRMPath == nil{
            globalOSRMPath = osrmPath
        }
        
        
        let url = self.url(forCalculating: options)
        print("calculateDirections:")
        print(url)
        let task = dataTask(with: url, completionHandler: { (json) in
            let response = options.response(from: json)
            if let routes = response.1 {
                for route in routes {
                    route.accessToken = self.accessToken
                    route.apiEndpoint = self.apiEndpoint
                    route.routeIdentifier = json["uuid"] as? String
                }
            }
            if globalOSRMPath == nil{
                completionHandler(response.0, response.1, nil)
            }
            else{
                let start = options.waypoints[0].coordinate
                let end = options.waypoints[1].coordinate
                let jsonResult = self.getJSON(start, end: end, osrmPath: globalOSRMPath!)
                
                let JSONString = self.getJSONString(jsonResult: jsonResult)
                print(JSONString)
                var json: JSONDictionary = [:]
                
//                    do {
////                        json = try JSONSerialization.jsonObject(with: , options: []) as! JSONDictionary
//                        json = try JSONSerialization.jsonObject(with: JSONString, options: <#T##JSONSerialization.ReadingOptions#>)
//                    } catch {
//                        assert(false, "Invalid data")
//                    }
                do{
                    let jsonData = try JSONSerialization.data(withJSONObject: jsonResult, options: JSONSerialization.WritingOptions.prettyPrinted)
                    json = try JSONSerialization.jsonObject(with: jsonData, options: []) as! JSONDictionary
                    let internalResponse = options.response(from: json)
                    if let routes = internalResponse.1 {
                        for route in routes {
                            route.accessToken = self.accessToken
                            route.apiEndpoint = self.apiEndpoint
                            route.routeIdentifier = json["uuid"] as? String
                        }
                    }
                    print("internalResponse0:")
                    print(internalResponse.0)
                    print("internalResponse1:")
                    print(internalResponse.1)
                    completionHandler(internalResponse.0, internalResponse.1, nil)
                    
                }
                catch {
                    print(error.localizedDescription)
                    completionHandler(nil, nil, nil)
                }
            
                
//                NSArray<MBRoute *> * _Nullable routes = [jsonResult valueForKeyPath:@"routes"];
//                let routes = jsonResult["routes"] as! [Route]
//                completionHandler(options.waypoints, routes, nil)
            }
//            completionHandler(response.0, response.1, nil)
        }) { (error) in
//

            if globalOSRMPath == nil{
                completionHandler(nil, nil, error)
            }
            else{
                let start = options.waypoints[0].coordinate
                let end = options.waypoints[1].coordinate
                let jsonResult = self.getJSON(start, end: end, osrmPath: globalOSRMPath!)
                let routes = jsonResult["routes"] as! [Route]
                completionHandler(options.waypoints, routes, nil)
            }
//            let xmlpath
//            let documentsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
//            let osrmPath = documentsDir + xmlpath + ".osrm"

        }
        task.resume()
        return task
    }

    /**
     Begins asynchronously calculating a match using the given options and delivers the results to a closure.


     - parameter options: A `MatchOptions` object specifying the requirements for the resulting match.
     - parameter completionHandler: The closure (block) to call with the resulting routes. This closure is executed on the application’s main thread.
     - returns: The data task used to perform the HTTP request. If, while waiting for the completion handler to execute, you no longer want the resulting routes, cancel this task.
     */
    @objc(calculateMatchesWithOptions:completionHandler:)
    @discardableResult open func calculate(_ options: MatchOptions, completionHandler: @escaping MatchCompletionHandler) -> URLSessionDataTask {
        let url = self.url(forCalculating: options)
        print("calculateMatches:")
        print(url)
        let data = options.encodedParam.data(using: .utf8)
        let task = dataTask(with: url, data: data, completionHandler: { (json) in
            let response = options.response(from: json)
            if let matches = response {
                for match in matches {
                    match.accessToken = self.accessToken
                    match.apiEndpoint = self.apiEndpoint
                    match.routeIdentifier = json["uuid"] as? String
                }
            }
//            let location = options.waypoints
//            completionHandler(response, nil)
        }) { (error) in
            completionHandler(nil, error)
        }
        task.resume()
        return task
    }

    @objc(calculateRoutesMatchingOptions:completionHandler:)
    @discardableResult open func calculateRoutes(matching options: MatchOptions, completionHandler: @escaping RouteCompletionHandler) -> URLSessionDataTask {
        let url = self.url(forCalculating: options)
        print("calculateRoutes:")
        print(url)
        let data = options.encodedParam.data(using: .utf8)
        let task = dataTask(with: url, data: data, completionHandler: { (json) in
            let response = options.response(containingRoutesFrom: json)
            if let routes = response.1 {
                for route in routes {
                    route.accessToken = self.accessToken
                    route.apiEndpoint = self.apiEndpoint
                    route.routeIdentifier = json["uuid"] as? String
                }
            }
            if globalOSRMPath == nil{
                completionHandler(response.0, response.1, nil)
            }
            else{
                let start = options.waypoints[0].coordinate
                let end = options.waypoints[1].coordinate
                let jsonResult = self.getJSON(start, end: end, osrmPath: globalOSRMPath!)
                //                NSArray<MBRoute *> * _Nullable routes = [jsonResult valueForKeyPath:@"routes"];
                let routes = jsonResult["routes"] as! [Route]
                completionHandler(options.waypoints, routes, nil)
            }
            //            completionHandler(response.0, response.1, nil)
        }) { (error) in
            //
            
            if globalOSRMPath == nil{
                completionHandler(nil, nil, error)
            }
            else{
                let start = options.waypoints[0].coordinate
                let end = options.waypoints[1].coordinate
                let jsonResult = self.getJSON(start, end: end, osrmPath: globalOSRMPath!)
                let routes = jsonResult["routes"] as! [Route]
                completionHandler(options.waypoints, routes, nil)
            }
        }
        task.resume()
        return task
    }

    /**
     Returns a URL session task for the given URL that will run the given closures on completion or error.

     - parameter url: The URL to request.
     - parameter completionHandler: The closure to call with the parsed JSON response dictionary.
     - parameter errorHandler: The closure to call when there is an error.
     - returns: The data task for the URL.
     - postcondition: The caller must resume the returned task.
     */
    fileprivate func dataTask(with url: URL, data: Data? = nil, completionHandler: @escaping (_ json: JSONDictionary) -> Void, errorHandler: @escaping (_ error: NSError) -> Void) -> URLSessionDataTask {

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        if let data = data {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.httpBody = data
        }

        return URLSession.shared.dataTask(with: request as URLRequest) { (data, response, error) in
            var json: JSONDictionary = [:]
            if let data = data, response?.mimeType == "application/json" {
                do {
                    json = try JSONSerialization.jsonObject(with: data, options: []) as! JSONDictionary
                } catch {
                    assert(false, "Invalid data")
                }
            }

            let apiStatusCode = json["code"] as? String
            let apiMessage = json["message"] as? String
            guard data != nil && error == nil && ((apiStatusCode == nil && apiMessage == nil) || apiStatusCode == "Ok") else {
                let apiError = Directions.informativeError(describing: json, response: response, underlyingError: error as NSError?)
                DispatchQueue.main.async {
                    errorHandler(apiError)
                }
                return
            }

            DispatchQueue.main.async {
                completionHandler(json)
            }
        }
    }

    /**
     The HTTP URL used to fetch the routes from the API.

     After requesting the URL returned by this method, you can parse the JSON data in the response and pass it into the `Route.init(json:waypoints:profileIdentifier:)` initializer.
     */
    @objc(URLForCalculatingDirectionsWithOptions:)
    open func url(forCalculating options: DirectionsOptions) -> URL {
        let params = options.params + [
            URLQueryItem(name: "access_token", value: accessToken),
        ]

        let unparameterizedURL = URL(string: options.path, relativeTo: apiEndpoint)!
        var components = URLComponents(url: unparameterizedURL, resolvingAgainstBaseURL: true)!
        components.queryItems = params
        return components.url!
    }

    /**
     Returns an error that supplements the given underlying error with additional information from the an HTTP response’s body or headers.
     */
    static func informativeError(describing json: JSONDictionary, response: URLResponse?, underlyingError error: NSError?) -> NSError {
        let apiStatusCode = json["code"] as? String
        var userInfo = error?.userInfo ?? [:]
        if let response = response as? HTTPURLResponse {
            var failureReason: String? = nil
            var recoverySuggestion: String? = nil
            switch (response.statusCode, apiStatusCode ?? "") {
            case (200, "NoRoute"):
                failureReason = "No route could be found between the specified locations."
                recoverySuggestion = "Make sure it is possible to travel between the locations with the mode of transportation implied by the profileIdentifier option. For example, it is impossible to travel by car from one continent to another without either a land bridge or a ferry connection."
            case (200, "NoSegment"):
                failureReason = "A specified location could not be associated with a roadway or pathway."
                recoverySuggestion = "Make sure the locations are close enough to a roadway or pathway. Try setting the coordinateAccuracy property of all the waypoints to a negative value."
            case (404, "ProfileNotFound"):
                failureReason = "Unrecognized profile identifier."
                recoverySuggestion = "Make sure the profileIdentifier option is set to one of the provided constants, such as MBDirectionsProfileIdentifierAutomobile."
            case (429, _):
                if let timeInterval = response.rateLimitInterval, let maximumCountOfRequests = response.rateLimit {
                    let intervalFormatter = DateComponentsFormatter()
                    intervalFormatter.unitsStyle = .full
                    let formattedInterval = intervalFormatter.string(from: timeInterval) ?? "\(timeInterval) seconds"
                    let formattedCount = NumberFormatter.localizedString(from: NSNumber(value: maximumCountOfRequests), number: .decimal)
                    failureReason = "More than \(formattedCount) requests have been made with this access token within a period of \(formattedInterval)."
                }
                if let rolloverTime = response.rateLimitResetTime {
                    let formattedDate = DateFormatter.localizedString(from: rolloverTime, dateStyle: .long, timeStyle: .long)
                    recoverySuggestion = "Wait until \(formattedDate) before retrying."
                }
            default:
                // `message` is v4 or v5; `error` is v4
                failureReason = json["message"] as? String ?? json["error"] as? String
            }
            userInfo[NSLocalizedFailureReasonErrorKey] = failureReason ?? userInfo[NSLocalizedFailureReasonErrorKey] ?? HTTPURLResponse.localizedString(forStatusCode: error?.code ?? -1)
            userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion ?? userInfo[NSLocalizedRecoverySuggestionErrorKey]
        }
        if let error = error {
            userInfo[NSUnderlyingErrorKey] = error
        }
        return NSError(domain: error?.domain ?? MBDirectionsErrorDomain, code: error?.code ?? -1, userInfo: userInfo)
    }
}

extension HTTPURLResponse {
    var rateLimit: UInt? {
        guard let limit = allHeaderFields["X-Rate-Limit-Limit"] as? String else {
            return nil
        }
        return UInt(limit)
    }

    var rateLimitInterval: TimeInterval? {
        guard let interval = allHeaderFields["X-Rate-Limit-Interval"] as? String else {
            return nil
        }
        return TimeInterval(interval)
    }

    var rateLimitResetTime: Date? {
        guard let resetTime = allHeaderFields["X-Rate-Limit-Reset"] as? String else {
            return nil
        }
        guard let resetTimeNumber = Double(resetTime) else {
            return nil
        }
        return Date(timeIntervalSince1970: resetTimeNumber)
    }

}
