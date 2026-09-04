import Foundation

public func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    assert(a == b, message.isEmpty ? "Assertion failed: \(a) != \(b)" : message, file: file, line: line)
}

public func XCTAssertTrue(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    assert(condition, message.isEmpty ? "Assertion failed: expected true" : message, file: file, line: line)
}

public func XCTAssertFalse(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    assert(!condition, message.isEmpty ? "Assertion failed: expected false" : message, file: file, line: line)
}

public func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    assert(a > b, message.isEmpty ? "Assertion failed: expected \(a) > \(b)" : message, file: file, line: line)
}

public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    assert(a >= b, message.isEmpty ? "Assertion failed: expected \(a) >= \(b)" : message, file: file, line: line)
}

public func XCTAssertNil(_ a: Any?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    assert(a == nil, message.isEmpty ? "Assertion failed: expected nil but got \(String(describing: a))" : message, file: file, line: line)
}

open class XCTestCase {
    public init() {}
    open func setUp() {}
    open func tearDown() {}
}

