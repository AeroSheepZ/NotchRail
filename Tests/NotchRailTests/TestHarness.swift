import Foundation

public func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    assert(a == b, "Assertion failed: \(a) != \(b)", file: file, line: line)
}

public func XCTAssertTrue(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    assert(condition, "Assertion failed: expected true", file: file, line: line)
}

public func XCTAssertFalse(_ condition: Bool, file: StaticString = #file, line: UInt = #line) {
    assert(!condition, "Assertion failed: expected false", file: file, line: line)
}

open class XCTestCase {
    public init() {}
    open func setUp() {}
    open func tearDown() {}
}
