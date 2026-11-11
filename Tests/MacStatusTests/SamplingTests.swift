import Testing
@testable import MacStatus

struct SamplingTests {
    @Test func aClosedPanelReadsOnlyTheMenuBarsMetrics() {
        let sampling = Sampling(demand: .menuBarOnly, menuBar: [.cpu, .temperature])
        #expect(sampling.cpu && !sampling.memory && !sampling.disk && !sampling.network && !sampling.apps)
        #expect(sampling.temperature == .cpu)
        #expect(sampling.interval == Sampling.menuBarInterval)
    }

    @Test func anEmptyMenuBarReadsNothing() {
        let sampling = Sampling(demand: .menuBarOnly, menuBar: [])
        #expect(!sampling.cpu && !sampling.memory && !sampling.disk && !sampling.network && !sampling.apps)
        #expect(sampling.temperature == nil)
    }

    @Test func theOverviewReadsEverySensorEveryPanelInterval() {
        let sampling = Sampling(demand: .overview, menuBar: [])
        #expect(sampling.cpu && sampling.memory && sampling.disk && sampling.network && !sampling.apps)
        #expect(sampling.temperature == .all)
        #expect(sampling.interval == Sampling.panelInterval)
    }

    @Test func pagesAddWhatTheyShowToTheMenuBarsMetrics() {
        let memory = Sampling(demand: .memory, menuBar: [.temperature])
        #expect(memory.memory && memory.apps && !memory.cpu && !memory.disk && !memory.network)
        #expect(memory.temperature == .cpu)
        #expect(memory.interval == Sampling.panelInterval)

        let tasks = Sampling(demand: .tasks, menuBar: [.cpu])
        #expect(tasks.tasks && tasks.cpu && !tasks.memory && !tasks.apps && !tasks.disk && !tasks.network)
        #expect(tasks.interval == Sampling.panelInterval)
        #expect(!memory.tasks && !Sampling(demand: .overview, menuBar: []).tasks)
    }
}
