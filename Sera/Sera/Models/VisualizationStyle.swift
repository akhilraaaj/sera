import Foundation

enum VisualizationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case ring
    case linear
    case grid
    case gauge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ring: return "Ring"
        case .linear: return "Linear"
        case .grid: return "Grid"
        case .gauge: return "Gauge"
        }
    }
}
