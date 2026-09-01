import Foundation
@testable import NotchRailKit

@MainActor
final class IslandStateMachineTests: XCTestCase {
    
    func testStateMachineTransitions() {
        PreferenceStore.shared.update { $0.triggerMode = .hover }
        
        let sm = IslandStateMachine()
        XCTAssertEqual(sm.currentState, .compact)
        
        // 移入感应区
        sm.handleMouseEnter(overflowCount: 2)
        XCTAssertEqual(sm.currentState, .hoverPending)
        
        // 快速划过移出
        sm.handleMouseLeave()
        XCTAssertEqual(sm.currentState, .compact)
        
        // 展开
        sm.triggerExpand(overflowCount: 2)
        XCTAssertEqual(sm.currentState, .extended)
        
        // 离开进入宽限期
        sm.handleMouseLeave()
        XCTAssertEqual(sm.currentState, .collapsing)
        
        // 宽限期内重新进入
        sm.handleMouseEnter(overflowCount: 2)
        XCTAssertEqual(sm.currentState, .extended)
        
        // 收起
        sm.triggerCollapse()
        XCTAssertEqual(sm.currentState, .compact)
    }
    
    func testClickOnlyTriggerMode() {
        PreferenceStore.shared.update { $0.triggerMode = .click }
        
        let sm = IslandStateMachine()
        XCTAssertEqual(sm.currentState, .compact)
        
        // 仅点击模式下：鼠标进入不触发防抖，保持 compact
        sm.handleMouseEnter(overflowCount: 3)
        XCTAssertEqual(sm.currentState, .compact)
        
        // 点击切换展开
        sm.toggleExpandCollapse(overflowCount: 3)
        XCTAssertEqual(sm.currentState, .extended)
        
        // 验证仅点击模式下鼠标移出不自动进入 collapsing 倒计时
        sm.handleMouseLeave()
        XCTAssertEqual(sm.currentState, .extended)
        
        // 再次点击切换收起
        sm.toggleExpandCollapse()
        XCTAssertEqual(sm.currentState, .compact)
        
        // 恢复默认
        PreferenceStore.shared.update { $0.triggerMode = .hover }
    }
    
    func testHoverAndClickTriggerMode() {
        PreferenceStore.shared.update { $0.triggerMode = .hoverAndClick }
        
        let sm = IslandStateMachine()
        XCTAssertEqual(sm.currentState, .compact)
        
        // 悬停进入正常触发 hoverPending
        sm.handleMouseEnter(overflowCount: 1)
        XCTAssertEqual(sm.currentState, .hoverPending)
        
        // 点击可立即打断防抖并展开
        sm.toggleExpandCollapse(overflowCount: 1)
        XCTAssertEqual(sm.currentState, .extended)
        
        // 恢复默认
        PreferenceStore.shared.update { $0.triggerMode = .hover }
    }
}
