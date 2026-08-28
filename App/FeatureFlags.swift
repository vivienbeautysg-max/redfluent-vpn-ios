import Foundation

enum FeatureFlags {
    /// Sign in with Apple 的入口开关。
    ///
    /// 2026-08-28 首次真机测试时 Apple 侧返回「Sign Up Not Completed」，请求根本没到我们的服务器。
    /// 我方配置已全部验证正确（二进制 entitlement、provisioning profile、ASC capability 三处都有），
    /// 对照公开报告，这是 capability 刚开通后 Apple 服务端传播延迟的已知现象。
    ///
    /// 首版上架期间先隐藏入口 —— 让审核员点到一个当前必然失败的按钮，
    /// 是在拿 Guideline 2.1（App Completeness）冒不必要的险。
    /// 后端两个端点、绑定与恢复逻辑、Owner 侧管控全部已上线并通过测试；
    /// Apple 侧恢复后把这里改成 true、重新发版即可，无需改动其他任何代码。
    static let appleSignInEnabled = false
}
