import CoreGraphics

/// 间距令牌。取值逐字来自 `docs/superpowers/DESIGN-SYSTEM.md` 第 3 节，统一 4 的倍数。
///
/// **页面内边距统一 `xl`（32），卡片内边距 `lg`（24）。**
/// 设计稿里的留白很足，那是它显得高级的主要原因——不要为了多塞内容压缩留白。
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let section: CGFloat = 40   // 大区块之间
}

/// 圆角令牌。同上，逐字来自第 3 节。
public enum Radius {
    public static let card: CGFloat = 12
    public static let control: CGFloat = 8
    public static let pill: CGFloat = 999
}

/// 描边宽度。规范第 4 节要求卡片用「发丝边框」分层，不用投影。
///
/// 单独立个令牌而不是在视图里写 `lineWidth: 1`，理由和颜色一样：
/// 边框粗细一旦散落到各个视图里，就再没有「统一改一次」的机会了。
public enum BorderWidth {
    public static let hairline: CGFloat = 1
}

/// 字距。规范第 4 节：区块标题的编号与英文标签「字距略宽」。
///
/// 这是规范里没给具体数值的地方，取 1.2pt——`.caption`（约 11pt）下约合 11%，
/// 看得出是标签而不至于散架。改它只改这一处。
public enum Tracking {
    public static let label: CGFloat = 1.2
}
