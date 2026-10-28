import XCTest
@testable import Vaani

final class PasteFocusResolverTests: XCTestCase {
    struct Node {
        var role: String = "AXGroup"
        var subrole: String? = nil
        var parent: Int? = nil
        var children: [Int] = []
        var focused = false
    }
    func resolver(_ nodes: [Int: Node]) -> PasteFocusResolver<Int> {
        PasteFocusResolver(role: { nodes[$0]?.role }, subrole: { nodes[$0]?.subrole },
            parent: { nodes[$0]?.parent }, children: { nodes[$0]?.children ?? [] },
            isFocused: { nodes[$0]?.focused ?? false }, same: ==)
    }
    func testNativeFieldAndContenteditableTextLeafResolveToEditor() throws {
        let focus = resolver([0: Node(role: "AXTextArea"), 1: Node(role: "AXStaticText", parent: 0)])
        XCTAssertEqual(try focus.resolve(0), 0)
        XCTAssertEqual(try focus.resolve(1), 0)
    }
    func testWebAreaWrapperResolvesOnlyFocusedEditor() throws {
        let focus = resolver([0: Node(role: "AXWebArea", children: [1, 2]),
                              1: Node(role: "AXTextArea", parent: 0),
                              2: Node(role: "AXTextArea", parent: 0, focused: true)])
        XCTAssertEqual(try focus.resolve(0), 2)
    }
    func testWebAreaFocusedTextLeafResolvesToItsContenteditableAncestor() throws {
        let focus = resolver([0: Node(role: "AXWebArea", children: [1, 2]),
                              1: Node(role: "AXTextArea", parent: 0),
                              2: Node(role: "AXTextArea", parent: 0, children: [3]),
                              3: Node(role: "AXStaticText", parent: 2, focused: true)])
        XCTAssertEqual(try focus.resolve(0), 2)
    }
    func testDoesNotGuessUnfocusedOrAmbiguousEditors() throws {
        var nodes = [0: Node(role: "AXWebArea", children: [1, 2]),
                     1: Node(role: "AXTextArea", parent: 0),
                     2: Node(role: "AXTextArea", parent: 0)]
        XCTAssertNil(try resolver(nodes).resolve(0))
        nodes[1]?.focused = true; nodes[2]?.focused = true
        XCTAssertNil(try resolver(nodes).resolve(0))
    }
    func testPasswordAncestorAndFocusedPasswordDescendantAreRejected() {
        let nested = resolver([0: Node(role: "AXTextField", subrole: "AXSecureTextField", children: [1]),
                               1: Node(role: "AXStaticText", parent: 0)])
        XCTAssertThrowsError(try nested.resolve(1))
        let wrapped = resolver([0: Node(role: "AXWebArea", children: [1]),
                                1: Node(role: "AXTextField", subrole: "AXSecureTextField", parent: 0, focused: true)])
        XCTAssertThrowsError(try wrapped.resolve(0))
    }
    func testCyclesAndOversizedTreesDoNotGuessDestination() throws {
        XCTAssertNil(try resolver([0: Node(parent: 1, children: [1]),
                                   1: Node(parent: 0, children: [0])]).resolve(0))
        var nodes = [0: Node(children: Array(1...150))]
        for id in 1...150 { nodes[id] = Node(role: "AXTextArea", parent: 0, focused: id == 1) }
        XCTAssertNil(try resolver(nodes).resolve(0))
    }
}
