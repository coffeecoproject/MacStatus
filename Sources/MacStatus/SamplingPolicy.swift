struct SamplingPolicy: Sendable {
    var expandedInterval: Duration = .seconds(2)
    var collapsedInterval: Duration = .seconds(5)
    var baselineInterval: Duration = .seconds(1)
    var readTimeout: Duration = .seconds(3)
    var maximumAge: Duration = .seconds(10)
}
