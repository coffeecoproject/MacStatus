import Testing
@testable import MacStatus

struct QuittableAppsTests {
    @Test(arguments: [
        ("/Applications/Claude.app", "/Applications/Claude.app", true),
        ("/Applications/Docker.app", "/Applications/Docker.app/Contents/MacOS/Docker Desktop.app", true),
        ("/Applications/Docker.app", "/Applications/Docker.app2", false),
        ("/Applications/Claude.app", "/Applications/Other.app", false)
    ])
    func appBelongsToTheRowBundleOrIsNestedInIt(row: String, appPath: String, expected: Bool) {
        #expect(QuittableApps.contains(row, appPath) == expected)
    }
}
