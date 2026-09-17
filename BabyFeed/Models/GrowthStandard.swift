import Foundation

/// Sex at birth. Needed only because WHO's growth standards are sex-specific –
/// a girl and a boy of the same weight sit on different percentiles.
enum BabySex: String, CaseIterable, Identifiable, Codable {
    case unspecified
    case female
    case male

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified: "Not set"
        case .female: "Girl"
        case .male: "Boy"
        }
    }

    /// Nil when it hasn't been set, which is what gates the percentile feature.
    var known: BabySex? { self == .unspecified ? nil : self }
}

/// Weight-for-age against the WHO Child Growth Standards.
///
/// WHO publishes the standards as Box-Cox (LMS) parameters, from which any
/// centile follows:
///
///     z = ((weight / M)^L − 1) / (L · S)      for L ≠ 0
///     z = ln(weight / M) / S                  for L = 0
///     weight = M · (1 + L · S · z)^(1/L)      (the inverse)
///
/// Everything here is pure arithmetic over a bundled table – no network, no
/// model, no measurable battery cost.
enum GrowthStandard {
    static let gramsPerKilogram = 1000.0

    /// L, M and S interpolated to an exact age, or nil outside birth to 24
    /// months, where these tables don't apply.
    ///
    /// WHO tabulates by week to 13 weeks and by month thereafter; between
    /// knots the parameters are interpolated linearly, which is what WHO's own
    /// tooling does for ages that fall between rows.
    static func parameters(ageDays: Double, sex: BabySex) -> WHOWeightForAge.Knot? {
        guard ageDays >= 0, ageDays <= WHOWeightForAge.maximumAgeDays else { return nil }
        let table = sex == .male ? WHOWeightForAge.boys : WHOWeightForAge.girls

        guard let upperIndex = table.firstIndex(where: { $0.ageDays >= ageDays }) else { return nil }
        let upper = table[upperIndex]
        guard upperIndex > 0, upper.ageDays > ageDays else { return upper }

        let lower = table[upperIndex - 1]
        let t = (ageDays - lower.ageDays) / (upper.ageDays - lower.ageDays)
        return WHOWeightForAge.Knot(
            ageDays: ageDays,
            l: lower.l + t * (upper.l - lower.l),
            m: lower.m + t * (upper.m - lower.m),
            s: lower.s + t * (upper.s - lower.s)
        )
    }

    /// How many standard deviations from the median this weight is.
    static func zScore(grams: Double, ageDays: Double, sex: BabySex) -> Double? {
        guard grams > 0, let p = parameters(ageDays: ageDays, sex: sex) else { return nil }
        let ratio = grams / gramsPerKilogram / p.m
        if abs(p.l) < 1e-10 {
            return log(ratio) / p.s
        }
        return (pow(ratio, p.l) - 1) / (p.l * p.s)
    }

    /// The weight sitting at a given z-score for this age.
    static func grams(zScore z: Double, ageDays: Double, sex: BabySex) -> Double? {
        guard let p = parameters(ageDays: ageDays, sex: sex) else { return nil }
        let kilograms: Double
        if abs(p.l) < 1e-10 {
            kilograms = p.m * exp(p.s * z)
        } else {
            let base = 1 + p.l * p.s * z
            // Outside the Box-Cox domain the curve has no real weight.
            guard base > 0 else { return nil }
            kilograms = p.m * pow(base, 1 / p.l)
        }
        return kilograms * gramsPerKilogram
    }

    /// Percentile (0–100) for a weight at an age.
    static func percentile(grams: Double, ageDays: Double, sex: BabySex) -> Double? {
        zScore(grams: grams, ageDays: ageDays, sex: sex).map { normalCDF($0) * 100 }
    }

    /// The weight sitting at a given percentile (0–100) for this age.
    static func grams(percentile: Double, ageDays: Double, sex: BabySex) -> Double? {
        grams(zScore: zScore(percentile: percentile), ageDays: ageDays, sex: sex)
    }

    // MARK: Normal distribution

    /// Φ(z) – the standard normal cumulative distribution.
    static func normalCDF(_ z: Double) -> Double {
        (1 + erf(z / 2.squareRoot())) / 2
    }

    /// Φ⁻¹(p) for a percentile in 0–100, by bisection.
    ///
    /// The closed-form approximations for the probit are easy to transcribe
    /// wrongly; bisecting a function known to be monotonic cannot be, and 80
    /// iterations is far below anything measurable here.
    static func zScore(percentile: Double) -> Double {
        let p = min(max(percentile / 100, 1e-12), 1 - 1e-12)
        var low = -8.0
        var high = 8.0
        for _ in 0..<80 {
            let mid = (low + high) / 2
            if normalCDF(mid) < p { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }
}
