import XCTest

/// 外部文件拖入任务条的几何路由纯函数（StripDropRouting.route）。
/// 布局假定："strip" 空间,中转格在 x=100..144,文件夹 chip 52pt 宽、8pt 间距从 x=152 起排。
final class StripDropRoutingTests: XCTestCase {
    private let shelf = CGRect(x: 100, y: 0, width: 44, height: 52)

    private func frames(_ paths: [String], startX: CGFloat = 152) -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        var x = startX
        for path in paths {
            result["folder-" + path] = CGRect(x: x, y: 0, width: 52, height: 52)
            x += 60
        }
        return result
    }

    func testHitShelfStashes() {
        let target = StripDropRouting.route(location: CGPoint(x: 120, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: shelf, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .stash)
    }

    func testLeftOfShelfIsNone() {
        let target = StripDropRouting.route(location: CGPoint(x: 50, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: shelf, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .none)
    }

    func testZeroShelfFrameRejectsEverything() {
        let target = StripDropRouting.route(location: CGPoint(x: 120, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: .zero, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .none)
    }

    func testNoFoldersPinsAtZeroWithinTailSlack() {
        // 中转格右缘 144 + 24pt 余量内 → 首次固定,插 0 位。
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: shelf, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .pin(insertIndex: 0))
    }

    func testDropOnLeftHalfOfFirstFolderMovesIntoIt() {
        let paths = ["/a", "/b"]
        // 第一个 chip 在 152..204；左右半都属于移入目标。
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testDropOnRightHalfOfFirstFolderMovesIntoIt() {
        let paths = ["/a", "/b"]
        let target = StripDropRouting.route(location: CGPoint(x: 190, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testDropUsesHorizontalChipBand() {
        let paths = ["/a"]
        let target = StripDropRouting.route(location: CGPoint(x: 180, y: 200),
                                            isApplicationDrag: false,
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testGapBetweenFoldersStillPins() {
        let paths = ["/a", "/b"]
        // 第一张右缘 204、第二张左缘 212；x=208 是真实 8pt 间隙。
        let target = StripDropRouting.route(location: CGPoint(x: 208, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 1))
    }

    func testMissingFrameDoesNotBecomeMoveTarget() {
        let paths = ["/a", "/b"]
        let partial = ["folder-/b": CGRect(x: 212, y: 0, width: 52, height: 52)]
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: shelf, folderFrames: partial, orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 0))
    }

    func testTailSlackAfterLastFolderPinsAtEnd() {
        let paths = ["/a", "/b"]
        // 第二 chip 右缘 264,+24 余量内 → 追加末位(2)。
        let target = StripDropRouting.route(location: CGPoint(x: 276, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 2))
    }

    func testFarRightIsNone() {
        let paths = ["/a", "/b"]
        let target = StripDropRouting.route(location: CGPoint(x: 400, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .none)
    }

    // MARK: - 中转格关掉（shelfFrame = nil）

    func testHiddenShelfStillMovesIntoFolders() {
        let paths = ["/a", "/b"]
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testHiddenShelfKeepsHeadSlackForInsertAtZero() {
        let paths = ["/a", "/b"]
        // 首个 chip 左缘 152，headSlack 8 → 144..152 是「插到最前面」的唯一落点。
        // 没有这段的话首个 chip 整段先被判成 moveInto，插 0 位就永远做不到了。
        let target = StripDropRouting.route(location: CGPoint(x: 147, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 0))
    }

    func testHiddenShelfRejectsLeftOfHeadSlack() {
        let paths = ["/a"]
        let target = StripDropRouting.route(location: CGPoint(x: 120, y: 26),
                                            isApplicationDrag: false,
                                            shelfFrame: nil, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .none, "中转格关掉后，它原来的位置不能再接收任何拖放")
    }

    func testHiddenShelfStillPinsInGapAndTailSlack() {
        let paths = ["/a", "/b"]
        XCTAssertEqual(
            StripDropRouting.route(location: CGPoint(x: 208, y: 26),
                                   isApplicationDrag: false,
                                   shelfFrame: nil, folderFrames: frames(paths), orderedPaths: paths),
            .pin(insertIndex: 1)
        )
        XCTAssertEqual(
            StripDropRouting.route(location: CGPoint(x: 276, y: 26),
                                   isApplicationDrag: false,
                                   shelfFrame: nil, folderFrames: frames(paths), orderedPaths: paths),
            .pin(insertIndex: 2)
        )
    }

    func testHiddenShelfWithNoFoldersRejectsEverything() {
        // 中转格关掉 + 一个固定文件夹都没有 → 文件夹区整体不存在，任务条上没有任何落点。
        // 这是已接受的边界：回路是菜单里把「显示中转站」勾回来。
        for x in [CGFloat(50), 120, 160, 400] {
            XCTAssertEqual(
                StripDropRouting.route(location: CGPoint(x: x, y: 26),
                                       isApplicationDrag: false,
                                       shelfFrame: nil, folderFrames: [:], orderedPaths: []),
                .none
            )
        }
    }

    // MARK: - 拖的是应用（安全边界）

    /// **本文件最要紧的一条**：应用永远只会得到 `.keepApp`。
    /// `.moveInto` 是真实的文件移动（同卷移动、跨卷复制）——漏一个应用进去就等于把它从
    /// 「应用程序」里搬走；`.pin` 会把它固定成一个展开 `.app` 内部结构的文件夹格子
    /// （2026-09-07 之前的真实 bug，`.app` 本身就是目录，`isDirectoryKey` 判不出来）。
    func testApplicationDragNeverReachesAnyFileTarget() {
        let paths = ["/a", "/b"]
        let folders = frames(paths)
        // 中转格上、首个文件夹格子上、格子之间的缝、尾部余量、条外、条最左端 —— 全覆盖。
        for x in [CGFloat(0), 50, 120, 147, 160, 190, 208, 276, 400, 2000] {
            for shelfFrame in [shelf, nil] {
                let target = StripDropRouting.route(location: CGPoint(x: x, y: 26),
                                                    isApplicationDrag: true,
                                                    shelfFrame: shelfFrame,
                                                    folderFrames: folders, orderedPaths: paths)
                XCTAssertEqual(target, .keepApp, "x=\(x) shelf=\(String(describing: shelfFrame))")
            }
        }
    }

    /// 中转格关掉 + 一个固定文件夹都没有 = 文件那条路整条都没有落点（已接受的边界），
    /// 但应用照样能落——这正是本次要补上的入口。
    func testApplicationDragLandsEvenWithNoFileDropTargetAtAll() {
        for x in [CGFloat(50), 120, 160, 400] {
            XCTAssertEqual(
                StripDropRouting.route(location: CGPoint(x: x, y: 26),
                                       isApplicationDrag: true,
                                       shelfFrame: nil,
                                       folderFrames: [:], orderedPaths: []),
                .keepApp
            )
        }
    }

    /// 反向锁：不是应用的时候，`.keepApp` 绝不会冒出来（否则普通文件也会去勾保留）。
    func testNonApplicationDragNeverKeepsAnApp() {
        let paths = ["/a", "/b"]
        for x in [CGFloat(0), 50, 120, 147, 160, 208, 276, 400] {
            XCTAssertNotEqual(
                StripDropRouting.route(location: CGPoint(x: x, y: 26),
                                       isApplicationDrag: false,
                                       shelfFrame: shelf,
                                       folderFrames: frames(paths), orderedPaths: paths),
                .keepApp
            )
        }
    }

    func testHiddenShelfIgnoresStaleShelfCoordinates() {
        // 视图侧必须传 nil 而不是旧帧：这条锁住「传了 nil 就绝不会再命中 stash」。
        let paths = ["/a"]
        let onShelfSpot = CGPoint(x: 120, y: 26)
        XCTAssertEqual(
            StripDropRouting.route(location: onShelfSpot,
                                   isApplicationDrag: false,
                                   shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths),
            .stash
        )
        XCTAssertEqual(
            StripDropRouting.route(location: onShelfSpot,
                                   isApplicationDrag: false,
                                   shelfFrame: nil, folderFrames: frames(paths), orderedPaths: paths),
            .none
        )
    }
}
