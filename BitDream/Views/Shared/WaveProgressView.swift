import SwiftUI

struct Wave: Shape {
    var offset: Angle
    var percent: Double
    var waveHeight: Double
    var frequency: Double
    
    var animatableData: Double {
        get { offset.degrees }
        set { offset = Angle(degrees: newValue) }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Calculate wave properties
        let width = rect.width
        let height = rect.height
        let midHeight = height * (1 - CGFloat(percent))
        let wavelength = width / CGFloat(frequency)
        
        // Start at the left edge
        path.move(to: CGPoint(x: 0, y: midHeight))
        
        // Draw the wave
        for x in stride(from: 0, through: width, by: 1) {
            let relativeX = x / wavelength
            let sine = sin(relativeX + CGFloat(offset.radians))
            let y = midHeight + CGFloat(waveHeight) * sine
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        // Complete the path by drawing to the bottom-right corner, then across the bottom, then back up
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        
        return path
    }
}

struct WaveProgressView: View {
    var progress: Double // 0.0 to 1.0
    var color: Color = .blue
    var secondaryColor: Color = .cyan
    
    @State private var waveOffset = Angle(degrees: 0)
    
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
            
            // First wave
            Wave(offset: waveOffset, percent: progress, waveHeight: 10, frequency: 6)
                .fill(color.opacity(0.7))
            
            // Second wave (offset slightly for effect)
            Wave(offset: waveOffset + Angle(degrees: 180), percent: progress, waveHeight: 8, frequency: 8)
                .fill(secondaryColor.opacity(0.5))
            
            // Progress text
            VStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(color)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(.title, design: .rounded).bold())
                    .foregroundColor(.primary)
            }
        }
        .frame(height: 150)
        .onAppear {
            withAnimation(Animation.linear(duration: 5).repeatForever(autoreverses: false)) {
                waveOffset = Angle(degrees: 360)
            }
        }
        .onChange(of: progress) { _, _ in
            // Restart animation when progress changes
            withAnimation(Animation.linear(duration: 5).repeatForever(autoreverses: false)) {
                waveOffset = Angle(degrees: 360)
            }
        }
    }
}

// Extension to make it easy to add wave progress to any view
extension View {
    func withWaveProgress(progress: Double, color: Color = .blue, secondaryColor: Color = .cyan) -> some View {
        VStack(spacing: 16) {
            self
            WaveProgressView(progress: progress, color: color, secondaryColor: secondaryColor)
                .padding(.horizontal)
        }
    }
}

// Preview
#Preview {
    VStack {
        WaveProgressView(progress: 0.25, color: .blue, secondaryColor: .cyan)
        WaveProgressView(progress: 0.5, color: .green, secondaryColor: .mint)
        WaveProgressView(progress: 0.75, color: .purple, secondaryColor: .indigo)
    }
    .padding()
} 