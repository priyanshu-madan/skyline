//
//  Globe3DView.swift
//  SkyLine
//
//  Real 3D globe using SceneKit for authentic Earth sphere experience
//

import SwiftUI
import SceneKit
import CoreLocation

struct Globe3DView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var flightStore: FlightStore
    
    @State private var scene = SCNScene()
    @State private var earthNode: SCNNode?
    @State private var cameraNode: SCNNode?
    @State private var isRotating = true
    @State private var rotationSpeed: Float = 0.5
    @State private var selectedFlight: Flight?
    @State private var showingFlightList = false
    @State private var flightNodes: [String: SCNNode] = [:]
    
    var body: some View {
        ZStack {
            // 3D Globe Scene
            SceneView(
                scene: scene,
                pointOfView: cameraNode,
                options: [.allowsCameraControl, .autoenablesDefaultLighting]
            )
            .ignoresSafeArea()
            .onAppear {
                setupScene()
            }
            .onDisappear {
                stopRotation()
            }
            
            // Control Panel
            VStack {
                HStack {
                    Spacer()
                    controlPanel
                }
                
                Spacer()
                
                // Bottom flight list toggle
                if !flightStore.flights.isEmpty {
                    bottomControls
                }
            }
            .padding()
            
            // Selected flight detail popup
            if let selectedFlight = selectedFlight {
                flightDetailPopup(flight: selectedFlight)
            }
        }
        .sheet(isPresented: $showingFlightList) {
            flightListSheet
        }
        .onChange(of: flightStore.flights) { _ in
            updateFlightAnnotations()
        }
    }
    
    // MARK: - Control Panel
    
    private var controlPanel: some View {
        VStack(spacing: 12) {
            // Theme Toggle
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                themeManager.toggleTheme()
                setupEarthMaterial() // Use existing function
            }) {
                Image(systemName: themeManager.currentTheme == .light ? "moon.fill" : "sun.max.fill")
                    .font(AppTypography.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(themeManager.currentTheme.colors.primary)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            
            // Rotation Toggle
            Button(action: toggleRotation) {
                Image(systemName: isRotating ? "pause.circle.fill" : "play.circle.fill")
                    .font(AppTypography.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(isRotating ? themeManager.currentTheme.colors.success : themeManager.currentTheme.colors.primary)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            
            // Rotation Speed Controls (when rotating)
            if isRotating {
                VStack(spacing: 4) {
                    Button(action: increaseSpeed) {
                        Image(systemName: "plus.circle.fill")
                            .font(AppTypography.flightTime)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(themeManager.currentTheme.colors.info)
                            .clipShape(Circle())
                    }
                    
                    Text("\(String(format: "%.1f", rotationSpeed))x")
                        .font(AppTypography.captionBold)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                        .frame(width: 32)
                    
                    Button(action: decreaseSpeed) {
                        Image(systemName: "minus.circle.fill")
                            .font(AppTypography.flightTime)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(themeManager.currentTheme.colors.warning)
                            .clipShape(Circle())
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .background(themeManager.currentTheme.colors.surface.opacity(0.9))
                .cornerRadius(8)
                .transition(.scale.combined(with: .opacity))
            }
            
            // Reset Camera
            Button(action: resetCamera) {
                Image(systemName: "scope")
                    .font(AppTypography.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(themeManager.currentTheme.colors.textSecondary)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
        }
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        HStack {
            Button(action: { showingFlightList = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(AppTypography.bodyBold)
                    
                    Text("\(flightStore.flights.count) Flights")
                        .font(AppTypography.bodyBold)
                    
                    Image(systemName: "chevron.up")
                        .font(AppTypography.captionBold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(themeManager.currentTheme.colors.primary)
                .cornerRadius(25)
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Flight Detail Popup & List Sheet (same as before)
    
    @ViewBuilder
    private func flightDetailPopup(flight: Flight) -> some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                HStack {
                    Text(flight.flightNumber)
                        .font(AppTypography.flightNumber)
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Spacer()
                    
                    Button(action: { selectedFlight = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppTypography.headline)
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(flight.departure.code)
                            .font(AppTypography.airportCode)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        Text(flight.departure.airport)
                            .font(AppTypography.flightStatus)
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                        Text(flight.departure.displayTime)
                            .font(AppTypography.flightTime)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                    
                    Spacer()
                    Image(systemName: "airplane")
                        .font(AppTypography.headline)
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                        .rotationEffect(.degrees(90))
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(flight.arrival.code)
                            .font(AppTypography.airportCode)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        Text(flight.arrival.airport)
                            .font(AppTypography.flightStatus)
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .lineLimit(1)
                        Text(flight.arrival.displayTime)
                            .font(AppTypography.flightTime)
                            .foregroundColor(themeManager.currentTheme.colors.text)
                    }
                }
                
                Button("Focus on Flight") {
                    focusOnFlight(flight)
                    selectedFlight = nil
                }
                .font(AppTypography.flightTime)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(themeManager.currentTheme.colors.primary)
                .cornerRadius(8)
            }
            .padding(20)
            .background(themeManager.currentTheme.colors.surface)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0), value: selectedFlight)
    }
    
    private var flightListSheet: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(flightStore.flights) { flight in
                        Button(action: {
                            focusOnFlight(flight)
                            selectedFlight = flight
                            showingFlightList = false
                        }) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(flight.flightNumber)
                                        .font(AppTypography.bodyBold)
                                        .foregroundColor(themeManager.currentTheme.colors.text)
                                    Text("\(flight.departure.code) → \(flight.arrival.code)")
                                        .font(AppTypography.body)
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(flight.status.displayName)
                                        .font(AppTypography.captionBold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(statusColor(for: flight.status))
                                        .cornerRadius(4)
                                    Text(flight.airline ?? "Unknown Airline")
                                        .font(AppTypography.footnote)
                                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                }
                                Image(systemName: "chevron.right")
                                    .font(AppTypography.captionBold)
                                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            }
                            .padding(16)
                            .background(themeManager.currentTheme.colors.surface)
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .background(themeManager.currentTheme.colors.background)
            .navigationTitle("Flights on Globe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        showingFlightList = false
                    }
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                }
            }
        }
    }
    
    // MARK: - 3D Scene Setup
    
    private func setupScene() {
        // Create Earth sphere
        let earthGeometry = SCNSphere(radius: 1.0)
        earthNode = SCNNode(geometry: earthGeometry)
        
        // Setup Earth material with texture
        setupEarthMaterial()
        
        // Position Earth at center
        earthNode?.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(earthNode!)
        
        // Setup camera
        cameraNode = SCNNode()
        cameraNode?.camera = SCNCamera()
        cameraNode?.position = SCNVector3(0, 0, 3.5) // Distance from Earth
        scene.rootNode.addChildNode(cameraNode!)
        
        // Setup lighting
        setupLighting()
        
        // Add flight annotations
        updateFlightAnnotations()
        
        // Start rotation
        startRotation()
    }
    
    private func setupEarthMaterial() {
        guard let earthNode = earthNode else { return }
        
        let material = SCNMaterial()
        
        // Try to use built-in Earth texture or create a detailed pattern
        if let earthTexture = createEarthTexture() {
            material.diffuse.contents = earthTexture
        } else {
            // Fallback to a more Earth-like appearance with gradient
            material.diffuse.contents = createEarthGradient()
        }
        
        // Add normal map for surface detail
        if let normalTexture = createNormalMap() {
            material.normal.contents = normalTexture
        }
        
        // Add specular highlights for ocean reflection
        material.specular.contents = createSpecularMap()
        material.shininess = 0.8
        
        // Add slight emission for city lights effect in dark areas
        material.emission.contents = createEmissionMap()
        
        earthNode.geometry?.materials = [material]
    }
    
    private func createEarthTexture() -> UIImage? {
        // Create a custom Earth texture with continents and oceans
        let size = CGSize(width: 1024, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            
            // Ocean base (blue)
            context.cgContext.setFillColor(UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0).cgColor)
            context.cgContext.fill(rect)
            
            // Add continent-like shapes
            context.cgContext.setFillColor(UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1.0).cgColor)
            
            // North America
            let northAmerica = CGRect(x: size.width * 0.15, y: size.height * 0.2, 
                                    width: size.width * 0.2, height: size.height * 0.3)
            context.cgContext.fillEllipse(in: northAmerica)
            
            // South America
            let southAmerica = CGRect(x: size.width * 0.2, y: size.height * 0.45, 
                                    width: size.width * 0.1, height: size.height * 0.35)
            context.cgContext.fillEllipse(in: southAmerica)
            
            // Europe/Africa
            let europeAfrica = CGRect(x: size.width * 0.45, y: size.height * 0.25, 
                                     width: size.width * 0.15, height: size.height * 0.5)
            context.cgContext.fillEllipse(in: europeAfrica)
            
            // Asia
            let asia = CGRect(x: size.width * 0.6, y: size.height * 0.15, 
                             width: size.width * 0.25, height: size.height * 0.4)
            context.cgContext.fillEllipse(in: asia)
            
            // Australia
            let australia = CGRect(x: size.width * 0.75, y: size.height * 0.6, 
                                  width: size.width * 0.08, height: size.height * 0.15)
            context.cgContext.fillEllipse(in: australia)
            
            // Add some cloud effects
            context.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.3).cgColor)
            for i in 0..<10 {
                let cloudRect = CGRect(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height),
                    width: size.width * CGFloat.random(in: 0.05...0.15),
                    height: size.height * CGFloat.random(in: 0.02...0.08)
                )
                context.cgContext.fillEllipse(in: cloudRect)
            }
        }
    }
    
    private func createEarthGradient() -> UIImage {
        // Create a fallback gradient that looks more Earth-like
        let size = CGSize(width: 512, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Create a radial gradient from blue (ocean) to green (land)
            let colors = [
                UIColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1.0).cgColor, // Ocean blue
                UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1.0).cgColor, // Land green
                UIColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1.0).cgColor  // Desert brown
            ]
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 0.5, 1.0])
            
            context.cgContext.drawLinearGradient(
                gradient!,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }
    }
    
    private func createNormalMap() -> UIImage? {
        // Create a simple normal map for surface texture
        let size = CGSize(width: 256, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor(red: 0.5, green: 0.5, blue: 1.0, alpha: 1.0).cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            
            // Add some random bumps for terrain
            for _ in 0..<50 {
                let bumpRect = CGRect(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height),
                    width: CGFloat.random(in: 5...20),
                    height: CGFloat.random(in: 5...20)
                )
                context.cgContext.setFillColor(UIColor(red: 0.6, green: 0.6, blue: 1.0, alpha: 0.5).cgColor)
                context.cgContext.fillEllipse(in: bumpRect)
            }
        }
    }
    
    private func createSpecularMap() -> UIImage {
        // Create specular map - oceans should be shiny, land should be matte
        let size = CGSize(width: 512, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            
            // Base ocean reflection (bright)
            context.cgContext.setFillColor(UIColor(white: 0.8, alpha: 1.0).cgColor)
            context.cgContext.fill(rect)
            
            // Land areas (darker, less reflective)
            context.cgContext.setFillColor(UIColor(white: 0.2, alpha: 1.0).cgColor)
            
            // Same continent shapes as main texture
            let northAmerica = CGRect(x: size.width * 0.15, y: size.height * 0.2, 
                                    width: size.width * 0.2, height: size.height * 0.3)
            context.cgContext.fillEllipse(in: northAmerica)
            
            let southAmerica = CGRect(x: size.width * 0.2, y: size.height * 0.45, 
                                    width: size.width * 0.1, height: size.height * 0.35)
            context.cgContext.fillEllipse(in: southAmerica)
            
            let europeAfrica = CGRect(x: size.width * 0.45, y: size.height * 0.25, 
                                     width: size.width * 0.15, height: size.height * 0.5)
            context.cgContext.fillEllipse(in: europeAfrica)
            
            let asia = CGRect(x: size.width * 0.6, y: size.height * 0.15, 
                             width: size.width * 0.25, height: size.height * 0.4)
            context.cgContext.fillEllipse(in: asia)
            
            let australia = CGRect(x: size.width * 0.75, y: size.height * 0.6, 
                                  width: size.width * 0.08, height: size.height * 0.15)
            context.cgContext.fillEllipse(in: australia)
        }
    }
    
    private func createEmissionMap() -> UIImage {
        // Create city lights effect
        let size = CGSize(width: 512, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            
            // Add small bright spots for major cities
            context.cgContext.setFillColor(UIColor.yellow.withAlphaComponent(0.6).cgColor)
            
            // Major cities (approximate positions)
            let cities = [
                CGPoint(x: size.width * 0.25, y: size.height * 0.35), // New York
                CGPoint(x: size.width * 0.5, y: size.height * 0.35),  // London
                CGPoint(x: size.width * 0.7, y: size.height * 0.4),   // Tokyo
                CGPoint(x: size.width * 0.55, y: size.height * 0.45), // Cairo
                CGPoint(x: size.width * 0.25, y: size.height * 0.55), // São Paulo
                CGPoint(x: size.width * 0.8, y: size.height * 0.65),  // Sydney
            ]
            
            for city in cities {
                let cityRect = CGRect(x: city.x - 2, y: city.y - 2, width: 4, height: 4)
                context.cgContext.fillEllipse(in: cityRect)
            }
        }
    }
    
    private func setupLighting() {
        // Ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.3, alpha: 1.0)
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)
        
        // Directional light (sun)
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.color = UIColor(white: 0.8, alpha: 1.0)
        let sunNode = SCNNode()
        sunNode.light = sunLight
        sunNode.position = SCNVector3(2, 2, 2)
        sunNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(sunNode)
    }
    
    private func updateFlightAnnotations() {
        // Remove existing flight nodes
        flightNodes.values.forEach { $0.removeFromParentNode() }
        flightNodes.removeAll()
        
        // Add new flight annotations
        for flight in flightStore.flights {
            addFlightAnnotation(for: flight)
        }
    }
    
    private func addFlightAnnotation(for flight: Flight) {
        guard let depCoordinate = flight.departure.coordinate else { return }
        
        // Convert lat/lon to 3D sphere coordinates
        let position = coordinateToSpherePosition(
            latitude: depCoordinate.latitude,
            longitude: depCoordinate.longitude,
            radius: 1.02 // Slightly above Earth surface
        )
        
        // Create flight pin
        let pinGeometry = SCNSphere(radius: 0.02)
        let pinNode = SCNNode(geometry: pinGeometry)
        
        // Set color based on flight status
        let material = SCNMaterial()
        material.diffuse.contents = uiColorFromStatus(flight.status)
        pinGeometry.materials = [material]
        
        pinNode.position = position
        scene.rootNode.addChildNode(pinNode)
        
        flightNodes[flight.id] = pinNode
    }
    
    private func coordinateToSpherePosition(latitude: Double, longitude: Double, radius: Float) -> SCNVector3 {
        let lat = Float(latitude * .pi / 180)
        let lon = Float(longitude * .pi / 180)
        
        let x = radius * cos(lat) * cos(lon)
        let y = radius * sin(lat)
        let z = radius * cos(lat) * sin(lon)
        
        return SCNVector3(x, y, z)
    }
    
    private func uiColorFromStatus(_ status: FlightStatus) -> UIColor {
        let color = statusColor(for: status)
        return UIColor(color)
    }
    
    // MARK: - Actions
    
    private func toggleRotation() {
        if isRotating {
            stopRotation()
        } else {
            startRotation()
        }
        isRotating.toggle()
    }
    
    private func startRotation() {
        let rotation = SCNAction.rotateBy(x: 0, y: CGFloat(2 * Float.pi * rotationSpeed), z: 0, duration: 10)
        let repeatRotation = SCNAction.repeatForever(rotation)
        earthNode?.runAction(repeatRotation, forKey: "rotation")
    }
    
    private func stopRotation() {
        earthNode?.removeAction(forKey: "rotation")
    }
    
    private func increaseSpeed() {
        rotationSpeed = min(rotationSpeed + 0.2, 2.0)
        if isRotating {
            stopRotation()
            startRotation()
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func decreaseSpeed() {
        rotationSpeed = max(rotationSpeed - 0.2, 0.1)
        if isRotating {
            stopRotation()
            startRotation()
        }
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func resetCamera() {
        cameraNode?.position = SCNVector3(0, 0, 3.5)
        cameraNode?.eulerAngles = SCNVector3(0, 0, 0)
    }
    
    private func focusOnFlight(_ flight: Flight) {
        guard let coordinate = flight.departure.coordinate else { return }
        
        let position = coordinateToSpherePosition(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: 2.0 // Camera distance
        )
        
        let moveAction = SCNAction.move(to: position, duration: 1.5)
        moveAction.timingMode = .easeInEaseOut
        cameraNode?.runAction(moveAction)
        
        // Make camera look at the flight location on Earth
        let lookAtPosition = coordinateToSpherePosition(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: 1.0
        )
        
        let lookAtAction = SCNAction.run { _ in
            self.cameraNode?.look(at: lookAtPosition)
        }
        
        cameraNode?.runAction(SCNAction.sequence([
            SCNAction.wait(duration: 0.5),
            lookAtAction
        ]))
    }
    
    private func statusColor(for status: FlightStatus) -> Color {
        switch status {
        case .boarding: return themeManager.currentTheme.colors.statusBoarding
        case .departed: return themeManager.currentTheme.colors.statusDeparted
        case .inAir: return themeManager.currentTheme.colors.statusInAir
        case .landed: return themeManager.currentTheme.colors.statusLanded
        case .delayed: return themeManager.currentTheme.colors.statusDelayed
        case .cancelled: return themeManager.currentTheme.colors.statusCancelled
        }
    }
}

#Preview {
    Globe3DView()
        .environmentObject(ThemeManager())
        .environmentObject(FlightStore())
}