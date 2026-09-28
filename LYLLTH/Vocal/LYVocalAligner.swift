import Accelerate
import Foundation

/// Lines a double up with a guide: which moment of the double matches each
/// moment of the guide, found by comparing their spectra every 10 ms and
/// taking the cheapest path through time (dynamic time warping).
enum LYVocalAligner {
    static let hopSeconds = 0.01
    static let bandCount = 14
    /// How far apart the two can start. Beyond this they are not the same line.
    static let searchSeconds = 0.8

    /// Spectral shape per 10 ms frame, levelled so a quieter double still
    /// matches a louder guide.
    static func features(_ samples: [Float], sampleRate: Double) -> [[Float]] {
        let factor = max(1, Int((sampleRate / 16_000).rounded()))
        let signal = LYVocalAnalyzer.decimate(samples, factor: factor)
        let rate = sampleRate / Double(factor)
        let size = 512
        let log2n = vDSP_Length(9)
        let hop = max(1, Int(rate * hopSeconds))
        guard signal.count > size, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        // Log-spaced bands, 100 Hz to 6 kHz.
        let edges = (0...bandCount).map { index -> Int in
            let hz = 100 * pow(60.0, Double(index) / Double(bandCount))
            return min(size / 2 - 1, max(1, Int(hz / rate * Double(size))))
        }
        let frameCount = (signal.count - size) / hop + 1
        var result = [[Float]](repeating: [Float](repeating: 0, count: bandCount), count: frameCount)
        var frame = [Float](repeating: 0, count: size)
        var real = [Float](repeating: 0, count: size / 2)
        var imaginary = [Float](repeating: 0, count: size / 2)
        var power = [Float](repeating: 0, count: size / 2)
        for index in 0..<frameCount {
            signal.withUnsafeBufferPointer { buffer in
                vDSP_vmul(buffer.baseAddress! + index * hop, 1, window, 1, &frame, 1, vDSP_Length(size))
            }
            real.withUnsafeMutableBufferPointer { realPointer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                    var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                    frame.withUnsafeBufferPointer { input in
                        input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                        }
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(size / 2))
                }
            }
            for band in 0..<bandCount {
                let low = edges[band], high = max(edges[band + 1], low + 1)
                var sum: Float = 0
                for bin in low..<high { sum += power[bin] }
                result[index][band] = log(1e-7 + sum / Float(high - low))
            }
        }
        // 50 ms smoothing: vibrato and single-period wobble are not timing.
        let raw = result
        for index in result.indices {
            let window = max(0, index - 2)...min(raw.count - 1, index + 2)
            for band in 0..<bandCount {
                result[index][band] = window.reduce(0) { $0 + raw[$1][band] } / Float(window.count)
            }
        }
        // Onsets: how fast overall level is rising. A word's attack is the
        // clearest landmark two performances share.
        let energy = raw.map { $0.reduce(0, +) / Float(bandCount) }
        for index in result.indices {
            let rise = max(0, energy[index] - energy[max(0, index - 3)])
            result[index].append(rise)
        }
        // Per feature: subtract the mean and scale to unit spread; onsets
        // weigh three bands' worth.
        for band in 0..<(bandCount + 1) {
            let values = result.map { $0[band] }
            let mean = values.reduce(0, +) / Float(max(values.count, 1))
            let spread = sqrt(values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(max(values.count, 1)))
            let weight: Float = band == bandCount ? 3 : 1
            for index in result.indices { result[index][band] = weight * (result[index][band] - mean) / max(spread, 1e-4) }
        }
        return result
    }

    /// For each guide frame, the double frame that matches it.
    static func path(guide: [[Float]], dub: [[Float]]) -> [Int] {
        let rows = guide.count, columns = dub.count
        guard rows > 0, columns > 0 else { return [] }
        let radius = Int(searchSeconds / hopSeconds)
        let width = 2 * radius + 1
        let slope = Double(columns) / Double(rows)
        func center(_ row: Int) -> Int { Int((Double(row) * slope).rounded()) }
        func distance(_ a: [Float], _ b: [Float]) -> Double {
            var dot: Float = 0, aa: Float = 0, bb: Float = 0
            vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
            vDSP_svesq(a, 1, &aa, vDSP_Length(a.count))
            vDSP_svesq(b, 1, &bb, vDSP_Length(b.count))
            return 1 - Double(dot) / max(Double(sqrt(aa * bb)), 1e-9)
        }
        // Banded cost and step tables: row r, band slot k is column center(r) - radius + k.
        let infinity = Double.greatestFiniteMagnitude / 4
        var cost = [Double](repeating: infinity, count: rows * width)
        var step = [UInt8](repeating: 0, count: rows * width)   // 0 diagonal, 1 from above, 2 from left
        let offDiagonal = 2.0
        // A flat cost for every change of timing. Inside a held vowel every
        // frame looks alike, and without this the path wanders after
        // vibrato; with it, timing only moves where the audio says so.
        let turn = 0.35
        for row in 0..<rows {
            let first = center(row) - radius
            for slot in 0..<width {
                let column = first + slot
                guard column >= 0, column < columns else { continue }
                let local = distance(guide[row], dub[column])
                if row == 0 && column <= radius {
                    // Free start anywhere near the beginning.
                    let left = slot > 0 ? cost[slot - 1] : infinity
                    cost[slot] = min(local, left < infinity ? left + local * offDiagonal : local)
                    step[slot] = left < infinity && left + local * offDiagonal < local ? 2 : 0
                    continue
                }
                var best = infinity, move: UInt8 = 0
                func previous(_ r: Int, _ c: Int) -> Double {
                    guard r >= 0 else { return infinity }
                    let k = c - (center(r) - radius)
                    return k >= 0 && k < width ? cost[r * width + k] : infinity
                }
                let diagonal = previous(row - 1, column - 1)
                if diagonal < infinity { best = diagonal + local; move = 0 }
                let above = previous(row - 1, column)
                if above < infinity, above + local * offDiagonal + turn < best { best = above + local * offDiagonal + turn; move = 1 }
                let left = slot > 0 ? cost[row * width + slot - 1] : infinity
                if left < infinity, left + local * offDiagonal + turn < best { best = left + local * offDiagonal + turn; move = 2 }
                cost[row * width + slot] = best
                step[row * width + slot] = move
            }
        }
        // End at the cheapest column near the end of the last row.
        var row = rows - 1
        var bestSlot = 0
        var bestCost = infinity
        for slot in 0..<width where cost[row * width + slot] < bestCost {
            bestCost = cost[row * width + slot]; bestSlot = slot
        }
        guard bestCost < infinity else { return Array(0..<rows).map { min(center($0), columns - 1) } }
        var column = center(row) - radius + bestSlot
        var match = [Int](repeating: 0, count: rows)
        match[row] = column
        while row > 0 || column > 0 {
            let slot = column - (center(row) - radius)
            guard slot >= 0, slot < width else { break }
            switch step[row * width + slot] {
            case 1: row -= 1
            case 2: column -= 1
            default: row -= 1; column -= 1
            }
            if row < 0 || column < 0 { break }
            match[row] = column
        }
        return match
    }

    /// Turns a frame match into a time map for the double.
    ///
    /// `guideTime(i)` and `dubTime(j)` convert frames to seconds in the
    /// double's source file. Tightness 0 leaves the timing alone; 1 follows
    /// the guide closely.
    static func warp(
        match: [Int],
        tightness: Double,
        outputTime: (Int) -> Double,
        sourceTime: (Int) -> Double
    ) -> [LYWarpPoint] {
        guard match.count > 2 else { return [] }
        let t = min(max(tightness, 0), 1)
        // Offsets in frames, smoothed: loose follows only the broad shape.
        let raw = match.enumerated().map { Double($0.element - $0.offset) }
        let width = max(5, Int((60 - 55 * t).rounded()))
        var smoothed = raw
        var sum = 0.0
        var window: [Double] = []
        for index in raw.indices {
            window.append(raw[index]); sum += raw[index]
            if window.count > width { sum -= window.removeFirst() }
            smoothed[index] = sum / Double(window.count)
        }
        // Centre the moving average.
        let shift = width / 2
        smoothed = raw.indices.map { smoothed[min($0 + shift, raw.count - 1)] }
        let amount = min(1, t * 2)
        var points: [LYWarpPoint] = []
        var lastSource = -Double.infinity
        for index in match.indices {
            let output = outputTime(index)
            let target = sourceTime(index + Int((smoothed[index] * amount).rounded()))
            var source = output + (target - output)
            // Never run backward, never faster than 4x.
            if points.last != nil {
                let previous = points[points.count - 1]
                let span = output - previous.output
                source = min(max(source, lastSource + span * 0.25), lastSource + span * 4)
            }
            points.append(LYWarpPoint(output: output, source: source))
            lastSource = source
        }
        return LYWarp.simplify(points, tolerance: 0.000_5)
    }
}
