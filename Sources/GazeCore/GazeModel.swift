import CoreGraphics

/// One calibration observation: what the face looked like while the user stared at a known point.
public struct GazeSample: Sendable, Equatable {
    public var features: GazeFeatures
    /// Target point in global screen coordinates (top-left origin, points).
    public var screenPoint: CGPoint

    public init(features: GazeFeatures, screenPoint: CGPoint) {
        self.features = features
        self.screenPoint = screenPoint
    }
}

public enum GazeModelError: Error, Equatable {
    case notEnoughSamples(required: Int, actual: Int)
    case singular
}

/// Ridge regression mapping ``GazeFeatures`` to a screen point.
///
/// Terms are standardized with the training mean and standard deviation before
/// fitting, so a single `ridgeLambda` behaves the same regardless of each term's units.
public struct GazeModel: Sendable, Equatable, Codable {
    public let means: [Double]
    public let deviations: [Double]
    /// Intercept followed by one weight per standardized term.
    public let weightsX: [Double]
    public let weightsY: [Double]

    /// Fits a model to calibration samples.
    ///
    /// - Parameters:
    ///   - samples: Observations collected while the user looked at known points.
    ///   - ridgeLambda: L2 penalty on the (standardized) term weights; the intercept is not penalized.
    /// - Returns: The fitted model.
    /// - Throws: ``GazeModelError/notEnoughSamples(required:actual:)`` when there are fewer
    ///   samples than unknowns, ``GazeModelError/singular`` when the system cannot be solved.
    public static func fit(samples: [GazeSample], ridgeLambda: Double = 1.0) throws -> GazeModel {
        let termCount = GazeFeatures.termCount
        let required = termCount + 1
        guard samples.count >= required else {
            throw GazeModelError.notEnoughSamples(required: required, actual: samples.count)
        }

        let rawRows = samples.map(\.features.terms)
        let count = Double(samples.count)
        var means = [Double](repeating: 0, count: termCount)
        var deviations = [Double](repeating: 0, count: termCount)
        for column in 0..<termCount {
            let mean = rawRows.reduce(0) { $0 + $1[column] } / count
            let variance = rawRows.reduce(0) { $0 + ($1[column] - mean) * ($1[column] - mean) } / count
            means[column] = mean
            deviations[column] = variance.squareRoot() > 1e-12 ? variance.squareRoot() : 1
        }

        let rows = rawRows.map { standardizedRow($0, means: means, deviations: deviations) }
        let size = required
        var normal = [[Double]](repeating: [Double](repeating: 0, count: size), count: size)
        var rhsX = [Double](repeating: 0, count: size)
        var rhsY = [Double](repeating: 0, count: size)
        for (row, sample) in zip(rows, samples) {
            for i in 0..<size {
                rhsX[i] += row[i] * sample.screenPoint.x
                rhsY[i] += row[i] * sample.screenPoint.y
                for j in 0..<size {
                    normal[i][j] += row[i] * row[j]
                }
            }
        }
        for i in 1..<size {
            normal[i][i] += ridgeLambda
        }

        guard
            let weightsX = solve(normal, rhsX),
            let weightsY = solve(normal, rhsY)
        else { throw GazeModelError.singular }

        return GazeModel(means: means, deviations: deviations, weightsX: weightsX, weightsY: weightsY)
    }

    /// Estimates where the user is looking.
    ///
    /// - Parameter features: Measurements from the current camera frame.
    /// - Returns: A point in global screen coordinates (top-left origin); it may fall off-screen.
    public func predict(_ features: GazeFeatures) -> CGPoint {
        let row = Self.standardizedRow(features.terms, means: means, deviations: deviations)
        let x = zip(row, weightsX).reduce(0) { $0 + $1.0 * $1.1 }
        let y = zip(row, weightsY).reduce(0) { $0 + $1.0 * $1.1 }
        return CGPoint(x: x, y: y)
    }

    private static func standardizedRow(_ terms: [Double], means: [Double], deviations: [Double]) -> [Double] {
        [1] + terms.indices.map { (terms[$0] - means[$0]) / deviations[$0] }
    }

    /// Solves `matrix · x = rhs` with Gaussian elimination and partial pivoting.
    private static func solve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix
        var b = rhs
        let n = b.count

        for pivotColumn in 0..<n {
            guard
                let pivotRow = (pivotColumn..<n).max(by: { abs(a[$0][pivotColumn]) < abs(a[$1][pivotColumn]) }),
                abs(a[pivotRow][pivotColumn]) > 1e-12
            else { return nil }
            a.swapAt(pivotColumn, pivotRow)
            b.swapAt(pivotColumn, pivotRow)

            for row in (pivotColumn + 1)..<n {
                let factor = a[row][pivotColumn] / a[pivotColumn][pivotColumn]
                guard factor != 0 else { continue }
                for column in pivotColumn..<n {
                    a[row][column] -= factor * a[pivotColumn][column]
                }
                b[row] -= factor * b[pivotColumn]
            }
        }

        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            let known = ((row + 1)..<n).reduce(0) { $0 + a[row][$1] * x[$1] }
            x[row] = (b[row] - known) / a[row][row]
        }
        return x
    }
}
