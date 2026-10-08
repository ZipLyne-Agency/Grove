import Foundation
import Testing
@testable import GroveCore

private func sortingRepo(_ id: Int, name: String, created: String?, pushed: String?, updated: String, stars: Int, issues: Int) throws -> Repository {
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture(name: name, id: id))) as! [String: Any]
    json["created_at"] = created
    json["pushed_at"] = (pushed as Any?) ?? NSNull()
    json["updated_at"] = updated
    json["stargazers_count"] = stars
    json["open_issues_count"] = issues
    return try JSONDecoder().decode(Repository.self, from: JSONSerialization.data(withJSONObject: json))
}

@Test func repositorySortsUseTheirOwnMetadataAndDirection() throws {
    let older = "2025-01-01T00:00:00Z", newer = "2026-01-01T00:00:00Z"
    let a = try sortingRepo(1, name: "alpha", created: older, pushed: newer, updated: older, stars: 9, issues: 1)
    let b = try sortingRepo(2, name: "beta", created: newer, pushed: older, updated: newer, stars: 1, issues: 9)
    let expected: [RepositorySort: [Int]] = [
        .createdNewest: [2, 1], .createdOldest: [1, 2],
        .pushed: [1, 2], .pushedOldest: [2, 1],
        .updatedNewest: [2, 1], .updatedOldest: [1, 2],
        .name: [1, 2], .nameDescending: [2, 1],
        .stars: [1, 2], .starsFewest: [2, 1],
        .issuesMost: [2, 1], .issuesFewest: [1, 2]
    ]
    for sort in RepositorySort.allCases {
        #expect(RepositoryQuery.filter([b, a], scope: .all, owner: nil, search: "", sort: sort).map(\.id) == expected[sort])
    }
    #expect(a.createdDate != nil)
}

@Test func missingDatesStayLastAndTiesAreStable() throws {
    let date = "2026-01-01T00:00:00Z"
    let a = try sortingRepo(1, name: "alpha", created: date, pushed: date, updated: date, stars: 0, issues: 0)
    let b = try sortingRepo(2, name: "beta", created: date, pushed: date, updated: date, stars: 0, issues: 0)
    let unknown = try sortingRepo(3, name: "aardvark", created: nil, pushed: nil, updated: date, stars: 0, issues: 0)
    for sort in [RepositorySort.createdNewest, .createdOldest, .pushed, .pushedOldest] {
        #expect(RepositoryQuery.filter([unknown, b, a], scope: .all, owner: nil, search: "", sort: sort).map(\.id) == [1, 2, 3])
    }
    #expect(unknown.createdDate == nil)
}
