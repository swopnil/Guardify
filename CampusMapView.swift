import SwiftUI
import MapKit
import CoreLocation


extension MKCoordinateRegion {
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let center = self.center
        let span = self.span
        
        let latDelta = span.latitudeDelta / 2.0
        let lonDelta = span.longitudeDelta / 2.0
        
        let minLat = center.latitude - latDelta
        let maxLat = center.latitude + latDelta
        let minLon = center.longitude - lonDelta
        let maxLon = center.longitude + lonDelta
        
        return (minLat...maxLat).contains(coordinate.latitude) &&
               (minLon...maxLon).contains(coordinate.longitude)
    }
    
    func isEqual(to other: MKCoordinateRegion, tolerance: CLLocationDegrees = 0.000001) -> Bool {
        return abs(self.center.latitude - other.center.latitude) < tolerance &&
               abs(self.center.longitude - other.center.longitude) < tolerance &&
               abs(self.span.latitudeDelta - other.span.latitudeDelta) < tolerance &&
               abs(self.span.longitudeDelta - other.span.longitudeDelta) < tolerance
    }
    
}
struct Person: Identifiable {
    let id = UUID()
    var location: CLLocationCoordinate2D
}



class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocationCoordinate2D?
    @Published var region: MKCoordinateRegion
    @Published var isWithinGeofence: Bool = true
    @Published var navigationState: NavigationState = .idle
    @Published var nextStep: String = ""
    
    let geofenceRegion: MKCoordinateRegion
    
    override init() {
        let center = CLLocationCoordinate2D(latitude: 40.0367, longitude: -75.3496)
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        
        geofenceRegion = MKCoordinateRegion(center: center, span: span)
        region = MKCoordinateRegion(center: center, span: span)
        
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    func startNavigation() {
         navigationState = .navigating
         updateNavigation()
     }
     
     func stopNavigation() {
         navigationState = .idle
         route = nil
         nextStep = ""
     }
     
     private func updateNavigation() {
         guard let userLocation = location, let route = route else { return }
         
         let closestStep = route.steps.min { stepA, stepB in
             stepA.distance(from: userLocation) < stepB.distance(from: userLocation)
         }
         
         if let step = closestStep {
             nextStep = step.instructions
         }
     }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last?.coordinate else { return }
            self.location = location
            isWithinGeofence = geofenceRegion.contains(location)
            
            if navigationState == .navigating {
                updateNavigation()
            }
        }
    

    func centerMapOnUser() {
        if let userLocation = location {
            region.center = userLocation
        }
    }
    @Published var route: MKRoute?
    @Published var destinationLocation: CLLocationCoordinate2D?

    func calculateRoute(to destination: CLLocationCoordinate2D, considering people: [Person]) {
        guard let userLocation = self.location else { return }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let response = response else { return }
            
            // Get all possible routes
            let routes = response.routes
            
            // Score routes based on proximity to people
            let scoredRoutes = routes.map { route -> (MKRoute, Double) in
                let score = self?.scoreRoute(route, considering: people) ?? 0
                return (route, score)
            }
            
            // Choose the route with the highest score
            if let bestRoute = scoredRoutes.max(by: { $0.1 < $1.1 })?.0 {
                DispatchQueue.main.async {
                    self?.route = bestRoute
                    self?.destinationLocation = destination
                }
            }
        }
    }

    private func scoreRoute(_ route: MKRoute, considering people: [Person]) -> Double {
        var score = 0.0
        let routePoints = route.polyline.points()
        let pointCount = route.polyline.pointCount

        for i in 0..<pointCount {
            let routePoint = routePoints[i]
            let coordinate = CLLocationCoordinate2D(latitude: routePoint.coordinate.latitude,
                                                    longitude: routePoint.coordinate.longitude)
            
            for person in people {
                let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: CLLocation(latitude: person.location.latitude, longitude: person.location.longitude))
                
                // Increase score for nearby people, with a maximum boost at 50 meters or closer
                if distance <= 50 {
                    score += 1.0
                } else if distance <= 200 {
                    score += 1.0 - (distance - 50) / 150
                }
            }
        }

        // Normalize score by route length to avoid favoring longer routes
        return score / Double(pointCount)
    }
}
enum NavigationState {
    case idle, navigating
}

extension MKRoute.Step {
    func distance(from location: CLLocationCoordinate2D) -> CLLocationDistance {
        return MKMapPoint(location).distance(to: polyline.points()[0])
    }
}



class APIManager: ObservableObject {
    @Published var people: [Person] = []
    private var timer: Timer?
    
    init() {
        startPolling()
    }
    
    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchPeopleLocations()
        }
    }
    
    func fetchPeopleLocations() {
        guard let url = URL(string: "http://10.130.18.36:500/api/people") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                let peopleData = try JSONDecoder().decode([PeopleData].self, from: data)
                DispatchQueue.main.async {
                    self?.people = peopleData.map { Person(location: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
                }
            } catch {
                print("Error decoding data: \(error.localizedDescription)")
            }
        }.resume()
    }
}

struct PeopleData: Codable {
    let latitude: Double
    let longitude: Double
}

class PeopleSimulator: ObservableObject {
    @Published var people: [Person] = []
    private var timer: Timer?
    private let regionCenter: CLLocationCoordinate2D
    private let regionSpan: MKCoordinateSpan
    
    init(center: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        self.regionCenter = center
        self.regionSpan = span
        generateInitialPeople()
        startSimulation()
    }
    
    private func generateInitialPeople() {
        for _ in 1...10 {
            let randomLat = regionCenter.latitude + Double.random(in: -regionSpan.latitudeDelta/4...regionSpan.latitudeDelta/4)
            let randomLon = regionCenter.longitude + Double.random(in: -regionSpan.longitudeDelta/4...regionSpan.longitudeDelta/4)
            people.append(Person(location: CLLocationCoordinate2D(latitude: randomLat, longitude: randomLon)))
        }
    }
    
    private func startSimulation() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePeopleLocations()
        }
    }
    
    private func updatePeopleLocations() {
        for i in 0..<people.count {
            let randomLatDelta = Double.random(in: -0.00005...0.00005)
            let randomLonDelta = Double.random(in: -0.00005...0.00005)
            
            let newLat = people[i].location.latitude + randomLatDelta
            let newLon = people[i].location.longitude + randomLonDelta
            
            people[i].location = CLLocationCoordinate2D(latitude: newLat, longitude: newLon)
        }
    }
}

struct InteractiveMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var people: [Person]
    let userLocation: CLLocationCoordinate2D?
    let route: MKRoute?
    let destinationLocation: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.setRegion(region, animated: true)
        
        // Remove existing annotations and overlays
        uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })
        uiView.removeOverlays(uiView.overlays)
        
        // Add people annotations
        let annotations = people.map { person -> MKPointAnnotation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = person.location
            return annotation
        }
        uiView.addAnnotations(annotations)
        
        // Add route overlay if available
        if let route = route {
            uiView.addOverlay(route.polyline)
        }
        
        // Add destination annotation if available
        if let destination = destinationLocation {
            let destinationAnnotation = MKPointAnnotation()
            destinationAnnotation.coordinate = destination
            destinationAnnotation.title = "Destination"
            uiView.addAnnotation(destinationAnnotation)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: InteractiveMapView

        init(_ parent: InteractiveMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            let identifier = "CustomPin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }

            if annotation.title == "Destination" {
                annotationView?.glyphImage = UIImage(systemName: "flag.fill")
                annotationView?.markerTintColor = .green
            } else {
                annotationView?.glyphImage = UIImage(systemName: "person.fill")
                annotationView?.markerTintColor = .red
            }

            return annotationView
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let routePolyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: routePolyline)
                renderer.strokeColor = .blue
                renderer.lineWidth = 5
                return renderer
            }
            return MKOverlayRenderer()
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            parent.region = mapView.region
        }
    }
}
struct CampusMapView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var peopleSimulator: PeopleSimulator
    @State private var showingDestinationPicker = false

    init() {
        let center = CLLocationCoordinate2D(latitude: 40.0367, longitude: -75.3496)
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        _peopleSimulator = StateObject(wrappedValue: PeopleSimulator(center: center, span: span))
    }

    var body: some View {
        ZStack {
            InteractiveMapView(region: $locationManager.region,
                               people: $peopleSimulator.people,
                               userLocation: locationManager.location,
                               route: locationManager.route,
                               destinationLocation: locationManager.destinationLocation)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Button(action: { showingDestinationPicker = true }) {
                        Image(systemName: "map")
                            .padding()
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    Spacer()
                    Button(action: locationManager.centerMapOnUser) {
                        Image(systemName: "location")
                            .padding()
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                }
                .padding()
                Spacer()
                if locationManager.navigationState == .navigating {
                    Text(locationManager.nextStep)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(radius: 2)
                    
                    Button(action: locationManager.stopNavigation) {
                        Text("End Navigation")
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                } else if locationManager.route != nil {
                    Button(action: locationManager.startNavigation) {
                        Text("Start Navigation")
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                if !locationManager.isWithinGeofence {
                    Text("You are outside the 19085 zip code area")
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingDestinationPicker) {
            DestinationPickerView(onDestinationSelected: handleDestinationSelected)
        }
    }

    func handleDestinationSelected(_ destination: CLLocationCoordinate2D) {
        locationManager.calculateRoute(to: destination, considering: peopleSimulator.people)
    }
}

struct DestinationPickerView: View {
    var onDestinationSelected: (CLLocationCoordinate2D) -> Void
    @Environment(\.presentationMode) var presentationMode

    let destinations = [
        "Dougherty Hall": CLLocationCoordinate2D(latitude: 40.03547, longitude: -75.34111),
        "Mendel Hall": CLLocationCoordinate2D(latitude: 40.0365, longitude: -75.3450),
        "Spit": CLLocationCoordinate2D(latitude: 40.03799, longitude: -75.3431),
        "Rudolph Hall": CLLocationCoordinate2D(latitude: 40.04162, longitude: -75.34312),
        "Connely Center": CLLocationCoordinate2D(latitude: 40.03578, longitude: -75.34023),
        "Bartley Hall": CLLocationCoordinate2D(latitude: 40.03467, longitude: -75.33824),


    ]

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(destinations.keys), id: \.self) { key in
                    Button(action: {
                        onDestinationSelected(destinations[key]!)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text(key)
                    }
                }
            }
            .navigationTitle("Choose Destination")
        }
    }
}
#Preview {
    CampusMapView()
}
