//
//  ContentView.swift
//  AIVideoDemo
//
//  Created by Martin Mitrevski on 10.2.25.
//

import SwiftUI
import StreamVideo

struct AISpeakingView: View {
    @ObservedObject var callState: CallState
    
    @State var amplitude: CGFloat = 0.0
        
    var body: some View {
        GlowView(amplitude: amplitude)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color.black)
            .onReceive(callState.$statsReport) { output in
                guard let statsReport = output?.subscriberRawStats?.statistics else { return }
                for (_, stats) in statsReport {
                    if stats.type == "inbound-rtp" {
                        if let audioLevel = stats.values["audioLevel"] as? Double {
                            amplitude = CGFloat(audioLevel)
                        }
                    }
                }
            }
    }
}

struct GlowView: View {
    /// Normalized audio level [0.0 ... 1.0]
    let amplitude: CGFloat
    
    @State private var time: CGFloat = 0
    @State private var rotationAngle: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // LAYER 1 (Outer)
                glowLayer(
                    baseRadiusMin: 150,   // radius at amplitude=0
                    baseRadiusMax: 250,  // radius at amplitude=1
                    blurRadius: 60,
                    baseOpacity: 0.35,
                    scaleRange: 0.3,   // how much amplitude grows it
                    waveRangeMin: 0.2, // bigger morph at low amplitude
                    waveRangeMax: 0.02, // smaller morph at high amplitude
                    geoSize: geo.size
                )
                
                // LAYER 2 (Mid)
                glowLayer(
                    baseRadiusMin: 100,
                    baseRadiusMax: 150,
                    blurRadius: 40,
                    baseOpacity: 0.55,
                    scaleRange: 0.3,
                    waveRangeMin: 0.15,
                    waveRangeMax: 0.03,
                    geoSize: geo.size
                )
                
                // LAYER 3 (Bright Core)
                glowLayer(
                    baseRadiusMin: 50,
                    baseRadiusMax: 100,
                    blurRadius: 20,
                    baseOpacity: 0.9,
                    scaleRange: 0.5,
                    waveRangeMin: 0.35,
                    waveRangeMax: 0.05,
                    geoSize: geo.size
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Rotate the entire glow. This ensures a unified rotation “centered” animation.
            .rotationEffect(.degrees(Double(rotationAngle)))
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        // Animate amplitude changes
        .animation(.easeInOut(duration: 0.2), value: amplitude)
        .onAppear {
            // Continuous rotation over ~10s
            let spinDuration: CGFloat = 10
            withAnimation(.linear(duration: Double(spinDuration)).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            
            // CADisplayLink for smooth ~60fps; we keep `time` in [0..1] to loop seamlessly
            let displayLink = CADisplayLink(target: DisplayLinkProxy { dt in
                let speed: CGFloat = 0.05
                let next = time + speed * CGFloat(dt)
                time = next.truncatingRemainder(dividingBy: 1.0)
            }, selector: #selector(DisplayLinkProxy.tick(_:)))
            displayLink.add(to: .main, forMode: .common)
        }
    }
    
    /// A single glow “layer” in the color scheme #00F9FF → #003AFF(transparent).
    /// - `baseRadiusMin` / `baseRadiusMax`: radius shrinks/grows with amplitude
    /// - `waveRangeMin` / `waveRangeMax`: morphing is stronger at low amplitude, weaker at high amplitude
    private func glowLayer(
        baseRadiusMin: CGFloat,
        baseRadiusMax: CGFloat,
        blurRadius: CGFloat,
        baseOpacity: CGFloat,
        scaleRange: CGFloat,
        waveRangeMin: CGFloat,
        waveRangeMax: CGFloat,
        geoSize: CGSize
    ) -> some View {
        
        // The actual radius = lerp from min->max based on amplitude
        let baseRadius = lerp(a: baseRadiusMin, b: baseRadiusMax, t: amplitude)
        
        // The waveRange also “lerps,” but we want big wave at low amplitude => waveRangeMin at amplitude=1
        // => just invert the parameter. Another approach: waveRange = waveRangeMax + (waveRangeMin-waveRangeMax)*(1 - amplitude).
        let waveRange = lerp(a: waveRangeMax, b: waveRangeMin, t: (1 - amplitude))
        
        // Our color gradient: #00F9FF center => #003AFF (transparent) edges
        let gradient = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Color(red: 0.0, green: 0.976, blue: 1.0), location: 0.0),
                .init(color: Color(red: 0.0, green: 0.227, blue: 1.0, opacity: 0.0), location: 1.0)
            ]),
            center: .center,
            startRadius: 0,
            endRadius: baseRadius
        )
        
        // Subtle elliptical warping from sin/cos
        let shapeWaveSin = sin(2 * .pi * time)
        let shapeWaveCos = cos(2 * .pi * time)
        
        // scale from amplitude
        let amplitudeScale = 1.0 + scaleRange * amplitude
        
        // final x/y scale => merges amplitude + wave
        let xScale = amplitudeScale + waveRange * shapeWaveSin
        let yScale = amplitudeScale + waveRange * shapeWaveCos
        
        return Ellipse()
            .fill(gradient)
            .opacity(baseOpacity)
            .scaleEffect(x: xScale, y: yScale)
            .blur(radius: blurRadius)
            .frame(width: geoSize.width, height: geoSize.height)
    }
    
    // Linear interpolation
    private func lerp(a: CGFloat, b: CGFloat, t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}

// MARK: - CADisplayLink Helper
fileprivate class DisplayLinkProxy {
    private let tickHandler: (CFTimeInterval) -> Void
    init(_ handler: @escaping (CFTimeInterval) -> Void) { self.tickHandler = handler }
    @objc func tick(_ link: CADisplayLink) { tickHandler(link.duration) }
}
