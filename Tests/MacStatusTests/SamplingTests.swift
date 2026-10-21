import Testing
@testable import MacStatus

struct SamplingTests {
    @Test func aClosedPanelReadsOnlyTheMenuBarsMetrics() {
        let sampling = Sampling(demand: .menuBarOnly, menuBar: [.cpu, .temperature])
        #expect(sampling.cpu && !sampling.memory && !sampling.disk && !sampling.apps)
        #expect(sampling.temperature == .cpu)
        #expect(sampling.interval == Sampling.menuBarInterval)
    }

    @Test func anEmptyMenuBarReadsNothing() {
        let sampling = Sampling(demand: .menuBarOnly, menuBar: [])
        #expect(!sampling.cpu && !sampling.memory && !sampling.disk && !sampling.apps)
        #expect(sampling.temperature == nil)
    }

    @Test func theOverviewReadsEverySensorEveryPanelInterval() {
        let sampling = Sampling(demand: .overview, menuBar: [])
        #expect(sampling.cpu && sampling.memory && sampling.disk && !sampling.apps)
        #expect(sampling.temperature == .all)
        #expect(sampling.interval == Sampling.panelInterval)
    }

    @Test func pagesAddWhatTheyShowToTheMenuBarsMetrics() {
        let processes = Sampling(demand: .processes, menuBar: [.temperature])
        #expect(processes.memory && processes.apps && !processes.cpu && !processes.disk)
        #expect(processes.temperature == .cpu)
        #expect(processes.interval == Sampling.panelInterval)

        let cleanup = Sampling(demand: .cleanup, menuBar: [.memory])
        #expect(cleanup.disk && cleanup.memory && !cleanup.cpu && !cleanup.apps)
        #expect(cleanup.temperature == nil)
        #expect(cleanup.interval == Sampling.menuBarInterval)
    }
}
