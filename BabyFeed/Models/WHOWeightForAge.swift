import Foundation

/// WHO Child Growth Standards, weight-for-age, birth to 24 months.
///
/// Generated from WHO's published tables – do not hand-edit. Weekly knots cover
/// birth to 13 weeks (where a newborn changes fastest) and monthly knots carry
/// it to 24 months. WHO's own weekly and monthly tables agree at birth and at
/// the 13-week/3-month seam, so the two splice cleanly.
///
/// Sources (percentile tables, which print L, M, S alongside the centiles):
/// https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-age/wfa-boys-0-13-percentiles.pdf
/// https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-age/wfa-girls-0-13-percentiles.pdf
/// https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-age/wfa-boys-0-5-percentiles.pdf
/// https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-age/wfa-girls-0-5-percentiles.pdf
enum WHOWeightForAge {
    /// One row of the standard: the Box-Cox parameters at a given age.
    struct Knot {
        let ageDays: Double
        /// Box-Cox power (skew).
        let l: Double
        /// Median weight in kilograms.
        let m: Double
        /// Coefficient of variation.
        let s: Double
    }

    /// WHO treats a month as 365.25 / 12 days.
    static let daysPerMonth = 365.25 / 12

    /// Oldest age the tables cover. Beyond this the standard doesn't apply.
    static let maximumAgeDays = 24 * daysPerMonth

    static let boys: [Knot] = [
        Knot(ageDays: 0.0000, l: 0.3487, m: 3.3464, s: 0.14602),
        Knot(ageDays: 7.0000, l: 0.2776, m: 3.4879, s: 0.14483),
        Knot(ageDays: 14.0000, l: 0.2581, m: 3.7529, s: 0.14142),
        Knot(ageDays: 21.0000, l: 0.2442, m: 4.0603, s: 0.13807),
        Knot(ageDays: 28.0000, l: 0.2331, m: 4.3671, s: 0.13497),
        Knot(ageDays: 35.0000, l: 0.2237, m: 4.659, s: 0.13215),
        Knot(ageDays: 42.0000, l: 0.2155, m: 4.9303, s: 0.1296),
        Knot(ageDays: 49.0000, l: 0.2081, m: 5.1817, s: 0.12729),
        Knot(ageDays: 56.0000, l: 0.2014, m: 5.4149, s: 0.1252),
        Knot(ageDays: 63.0000, l: 0.1952, m: 5.6319, s: 0.1233),
        Knot(ageDays: 70.0000, l: 0.1894, m: 5.8346, s: 0.12157),
        Knot(ageDays: 77.0000, l: 0.184, m: 6.0242, s: 0.12001),
        Knot(ageDays: 84.0000, l: 0.1789, m: 6.2019, s: 0.1186),
        Knot(ageDays: 91.0000, l: 0.174, m: 6.369, s: 0.11732),
        Knot(ageDays: 121.7500, l: 0.1553, m: 7.0023, s: 0.11316),
        Knot(ageDays: 152.1875, l: 0.1395, m: 7.5105, s: 0.1108),
        Knot(ageDays: 182.6250, l: 0.1257, m: 7.934, s: 0.10958),
        Knot(ageDays: 213.0625, l: 0.1134, m: 8.297, s: 0.10902),
        Knot(ageDays: 243.5000, l: 0.1021, m: 8.6151, s: 0.10882),
        Knot(ageDays: 273.9375, l: 0.0917, m: 8.9014, s: 0.10881),
        Knot(ageDays: 304.3750, l: 0.082, m: 9.1649, s: 0.10891),
        Knot(ageDays: 334.8125, l: 0.073, m: 9.4122, s: 0.10906),
        Knot(ageDays: 365.2500, l: 0.0644, m: 9.6479, s: 0.10925),
        Knot(ageDays: 395.6875, l: 0.0563, m: 9.8749, s: 0.10949),
        Knot(ageDays: 426.1250, l: 0.0487, m: 10.0953, s: 0.10976),
        Knot(ageDays: 456.5625, l: 0.0413, m: 10.3108, s: 0.11007),
        Knot(ageDays: 487.0000, l: 0.0343, m: 10.5228, s: 0.11041),
        Knot(ageDays: 517.4375, l: 0.0275, m: 10.7319, s: 0.11079),
        Knot(ageDays: 547.8750, l: 0.0211, m: 10.9385, s: 0.11119),
        Knot(ageDays: 578.3125, l: 0.0148, m: 11.143, s: 0.11164),
        Knot(ageDays: 608.7500, l: 0.0087, m: 11.3462, s: 0.11211),
        Knot(ageDays: 639.1875, l: 0.0029, m: 11.5486, s: 0.11261),
        Knot(ageDays: 669.6250, l: -0.0028, m: 11.7504, s: 0.11314),
        Knot(ageDays: 700.0625, l: -0.0083, m: 11.9514, s: 0.11369),
        Knot(ageDays: 730.5000, l: -0.0137, m: 12.1515, s: 0.11426),
    ]

    static let girls: [Knot] = [
        Knot(ageDays: 0.0000, l: 0.3809, m: 3.2322, s: 0.14171),
        Knot(ageDays: 7.0000, l: 0.2671, m: 3.3388, s: 0.146),
        Knot(ageDays: 14.0000, l: 0.2304, m: 3.5693, s: 0.14339),
        Knot(ageDays: 21.0000, l: 0.2024, m: 3.8352, s: 0.1406),
        Knot(ageDays: 28.0000, l: 0.1789, m: 4.0987, s: 0.13805),
        Knot(ageDays: 35.0000, l: 0.1582, m: 4.3476, s: 0.13583),
        Knot(ageDays: 42.0000, l: 0.1395, m: 4.5793, s: 0.13392),
        Knot(ageDays: 49.0000, l: 0.1224, m: 4.795, s: 0.13228),
        Knot(ageDays: 56.0000, l: 0.1065, m: 4.9959, s: 0.13087),
        Knot(ageDays: 63.0000, l: 0.0918, m: 5.1842, s: 0.12966),
        Knot(ageDays: 70.0000, l: 0.0779, m: 5.3618, s: 0.12861),
        Knot(ageDays: 77.0000, l: 0.0648, m: 5.5295, s: 0.1277),
        Knot(ageDays: 84.0000, l: 0.0525, m: 5.6883, s: 0.12691),
        Knot(ageDays: 91.0000, l: 0.0407, m: 5.8393, s: 0.12622),
        Knot(ageDays: 121.7500, l: -0.005, m: 6.4237, s: 0.12402),
        Knot(ageDays: 152.1875, l: -0.043, m: 6.8985, s: 0.12274),
        Knot(ageDays: 182.6250, l: -0.0756, m: 7.297, s: 0.12204),
        Knot(ageDays: 213.0625, l: -0.1039, m: 7.6422, s: 0.12178),
        Knot(ageDays: 243.5000, l: -0.1288, m: 7.9487, s: 0.12181),
        Knot(ageDays: 273.9375, l: -0.1507, m: 8.2254, s: 0.12199),
        Knot(ageDays: 304.3750, l: -0.17, m: 8.48, s: 0.12223),
        Knot(ageDays: 334.8125, l: -0.1872, m: 8.7192, s: 0.12247),
        Knot(ageDays: 365.2500, l: -0.2024, m: 8.9481, s: 0.12268),
        Knot(ageDays: 395.6875, l: -0.2158, m: 9.1699, s: 0.12283),
        Knot(ageDays: 426.1250, l: -0.2278, m: 9.387, s: 0.12294),
        Knot(ageDays: 456.5625, l: -0.2384, m: 9.6008, s: 0.12299),
        Knot(ageDays: 487.0000, l: -0.2478, m: 9.8124, s: 0.12303),
        Knot(ageDays: 517.4375, l: -0.2562, m: 10.0226, s: 0.12306),
        Knot(ageDays: 547.8750, l: -0.2637, m: 10.2315, s: 0.12309),
        Knot(ageDays: 578.3125, l: -0.2703, m: 10.4393, s: 0.12315),
        Knot(ageDays: 608.7500, l: -0.2762, m: 10.6464, s: 0.12323),
        Knot(ageDays: 639.1875, l: -0.2815, m: 10.8534, s: 0.12335),
        Knot(ageDays: 669.6250, l: -0.2862, m: 11.0608, s: 0.1235),
        Knot(ageDays: 700.0625, l: -0.2903, m: 11.2688, s: 0.12369),
        Knot(ageDays: 730.5000, l: -0.2941, m: 11.4775, s: 0.1239),
    ]
}
