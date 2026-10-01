/// Solves `matrix · x = rhs` with Gaussian elimination and partial pivoting.
///
/// - Returns: The solution, or `nil` when the matrix is (numerically) singular.
func solveLinearSystem(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
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
