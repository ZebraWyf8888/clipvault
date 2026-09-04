import Foundation

/// 基于常见凭证格式的启发式检测（gitleaks 风格的规则子集）。
/// 只用于决定「不记录」或「遮罩显示」，宁可误报也不放过明显的 token。
public enum SecretDetector {
    /// 超长文本只扫描前 200 KB，避免大段代码/日志拖慢主线程。
    private static let maxScanLength = 200 * 1024

    private static let patternSources: [String] = [
        // 云厂商 / 平台 access key
        #"\bAKIA[0-9A-Z]{16}\b"#,                        // AWS access key
        #"\bASIA[0-9A-Z]{16}\b"#,                        // AWS STS key
        #"\bAIza[0-9A-Za-z_\-]{30,}\b"#,                 // Google API key
        // 代码托管 / CI
        #"\bgh[pousr]_[A-Za-z0-9]{20,}\b"#,              // GitHub token
        #"\bgithub_pat_[A-Za-z0-9_]{20,}\b"#,            // GitHub fine-grained PAT
        #"\bglpat-[A-Za-z0-9_\-]{20,}\b"#,               // GitLab PAT
        #"\bnpm_[A-Za-z0-9]{36}\b"#,                     // npm token
        // SaaS
        #"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"#,            // Slack token
        #"\bsk_live_[0-9a-zA-Z]{16,}\b"#,                // Stripe live secret
        #"\brk_live_[0-9a-zA-Z]{16,}\b"#,                // Stripe restricted
        #"\bsk-[A-Za-z0-9_\-]{20,}\b"#,                  // OpenAI 风格 key
        // 通用格式
        #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}\b"#, // JWT
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,          // PEM 私钥
        #"(?i)\bbearer\s+[A-Za-z0-9._\-]{20,}"#,         // Bearer token
        #"(?i)\b(api[_-]?key|access[_-]?token|secret[_-]?key|client[_-]?secret|passwd|password)\b\s*[:=]\s*['"]?[^\s'"]{8,}"#,
    ]

    private static let patterns: [NSRegularExpression] = patternSources.compactMap {
        try? NSRegularExpression(pattern: $0)
    }

    public static func looksLikeSecret(_ text: String) -> Bool {
        let scanned = text.count > maxScanLength ? String(text.prefix(maxScanLength)) : text
        let range = NSRange(scanned.startIndex..., in: scanned)
        for p in patterns where p.firstMatch(in: scanned, range: range) != nil {
            return true
        }
        return false
    }
}
