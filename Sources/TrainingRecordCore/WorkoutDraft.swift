import Foundation

/// 录入一组时的输入错误。重量与次数都非法时报告重量（先校验重量）。
public enum SetInputError: Error, Equatable, Sendable {
    /// 重量不是 0…1000 之间的数字。
    case invalidWeight
    /// 次数不是 1…1000 之间的整数。
    case invalidReps
}

/// 录入中的一组：已通过校验的重量 × 次数。
public struct SetDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 重量（kg），0…1000。
    public let weight: Double
    /// 次数，1…1000。
    public let reps: Int

    init(id: UUID = UUID(), weight: Double, reps: Int) {
        self.id = id
        self.weight = weight
        self.reps = reps
    }
}

/// 录入中的一个动作及其已添加的组（按录入顺序）。
public struct ExerciseDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 动作名，已去掉首尾空白，非空。
    public let name: String
    /// 已添加的组，按录入顺序。
    public internal(set) var sets: [SetDraft]

    init(id: UUID = UUID(), name: String, sets: [SetDraft] = []) {
        self.id = id
        self.name = name
        self.sets = sets
    }
}

/// 组输入解析：把文本框里的重量、次数转换成数值。界面层可用它做即时校验。
public enum SetInputParser {
    /// 允许的重量范围（kg）。0 用于自重动作。
    public static let weightRange: ClosedRange<Double> = 0...1000
    /// 允许的次数范围。
    public static let repsRange: ClosedRange<Int> = 1...1000

    /// 重量：去首尾空白，逗号视作小数点；只接受十进制数字和至多一个小数点，且落在 `weightRange` 内。
    public static func parseWeight(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        var digitCount = 0
        var dotCount = 0
        for character in normalized {
            if isASCIIDigit(character) {
                digitCount += 1
            } else if character == "." {
                dotCount += 1
            } else {
                return nil
            }
        }
        guard digitCount > 0, dotCount <= 1, let value = Double(normalized), value.isFinite else {
            return nil
        }
        return weightRange.contains(value) ? value : nil
    }

    /// 次数：去首尾空白，只接受十进制数字组成的整数，且落在 `repsRange` 内。
    public static func parseReps(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(isASCIIDigit), let value = Int(trimmed) else {
            return nil
        }
        return repsRange.contains(value) ? value : nil
    }

    /// 先校验重量，再校验次数。
    public static func parseSet(weightText: String, repsText: String) -> Result<SetDraft, SetInputError> {
        guard let weight = parseWeight(weightText) else { return .failure(.invalidWeight) }
        guard let reps = parseReps(repsText) else { return .failure(.invalidReps) }
        return .success(SetDraft(weight: weight, reps: reps))
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return false }
        return ascii >= 48 && ascii <= 57
    }
}
