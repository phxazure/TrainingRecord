import SwiftUI
import TrainingRecordCore

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("TrainingRecord").font(.title)
            Text(TrainingRecordInfo.version).foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview { ContentView() }
