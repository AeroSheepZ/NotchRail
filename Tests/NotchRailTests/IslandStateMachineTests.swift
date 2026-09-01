import Foundation
@testable import NotchRailKit

@MainActor
final class IslandStateMachineTests: XCTestCase {
    
    func testStateMachineTransitions() {
        let sm = IslandStateMachine()
        XCTAssertEqual(sm.currentState, .compact)
        
        // 移入感应区
        sm.handleMouseEnter()
        XCTAssertEqual(sm.currentState, .hoverPending)
        
        // 快速划过移出
        sm.handleMouseLeave()
        XCTAssertEqual(sm.currentState, .compact)
        
        // 展开
        sm.triggerExpand()
        XCTAssertEqual(sm.currentState, .extended)
        
        // 离开进入宽限期
        sm.handleMouseLeave()
        XCTAssertEqual(sm.currentState, .collapsing)
        
        // 宽限期内重新进入
        sm.handleMouseEnter()
        XCTAssertEqual(sm.currentState, .extended)
        
        // 收起
        sm.triggerCollapse()
        XCTAssertEqual(sm.currentState, .compact)
        
        // 零项抑制测试：overflowCount == 0 时 handleMouseEnter 不触发展开
        sm.handleMouseEnter(overflowCount: 0)
        XCTAssertEqual(sm.currentState, .compact)
    }
}
