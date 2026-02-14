// =============================================================================
// BASICToken.swift - Atari BASIC Token Definitions
// =============================================================================
//
// This file defines all token types used in Atari BASIC's tokenized format.
// Atari BASIC stores programs in a compact tokenized form where keywords,
// operators, and functions are represented by single-byte tokens.
//
// Token ranges (statement name position — first byte of each statement):
// - $00-$36: Statement tokens (REM, PRINT, FOR, etc.)
//
// Token ranges (expression position — all other bytes):
// - $0E + 6 bytes: BCD floating-point constant
// - $0F + length + chars: String constant
// - $12-$37: Operator tokens (arithmetic, comparison, logical)
// - $38-$4F: Function tokens (STR$, CHR$, ABS, etc.)
// - $16: End of line marker (also operator token .endOfLine)
// - $80-$FF: Variable reference (index into Variable Name Table)
//
// IMPORTANT: Operator values $12-$36 overlap with statement tokens.
// Context determines interpretation: the byte immediately after the line
// header (and after each colon separator) is always a statement name token;
// all other bytes use the expression token space.
//
// Reference: Atari BASIC Reference Manual, De Re Atari Chapter 8
//
// =============================================================================

import Foundation

// =============================================================================
// MARK: - Statement Tokens ($00-$36)
// =============================================================================

/// Statement tokens represent BASIC keywords that begin statements.
///
/// These are the primary command words in Atari BASIC. Each statement token
/// has a unique byte value in the range $00-$36.
public enum BASICStatementToken: UInt8, CaseIterable, Sendable {
    case rem = 0x00
    case data = 0x01
    case input = 0x02
    case color = 0x03
    case list = 0x04
    case enter = 0x05
    case letStatement = 0x06      // Explicit LET
    case ifStatement = 0x07
    case forStatement = 0x08
    case next = 0x09
    case goto = 0x0A
    case goTo = 0x0B              // "GO TO" (two words)
    case gosub = 0x0C
    case trap = 0x0D
    case bye = 0x0E
    case cont = 0x0F
    case com = 0x10               // Same as DIM
    case close = 0x11
    case clr = 0x12
    case deg = 0x13
    case dim = 0x14
    case end = 0x15
    case new = 0x16
    case open = 0x17
    case load = 0x18
    case save = 0x19
    case status = 0x1A
    case note = 0x1B
    case point = 0x1C
    case xio = 0x1D
    case on = 0x1E
    case poke = 0x1F
    case print = 0x20
    case rad = 0x21
    case read = 0x22
    case restore = 0x23
    case returnStatement = 0x24
    case run = 0x25
    case stop = 0x26
    case pop = 0x27
    case printShort = 0x28        // "?" shorthand for PRINT
    case get = 0x29
    case put = 0x2A
    case graphics = 0x2B
    case plot = 0x2C
    case position = 0x2D
    case dos = 0x2E
    case drawto = 0x2F
    case setcolor = 0x30
    case locate = 0x31
    case sound = 0x32
    case lprint = 0x33
    case csave = 0x34
    case cload = 0x35
    case impliedLet = 0x36        // Assignment without LET keyword

    /// The keyword string for this token.
    public var keyword: String {
        switch self {
        case .rem: return "REM"
        case .data: return "DATA"
        case .input: return "INPUT"
        case .color: return "COLOR"
        case .list: return "LIST"
        case .enter: return "ENTER"
        case .letStatement: return "LET"
        case .ifStatement: return "IF"
        case .forStatement: return "FOR"
        case .next: return "NEXT"
        case .goto: return "GOTO"
        case .goTo: return "GO TO"
        case .gosub: return "GOSUB"
        case .trap: return "TRAP"
        case .bye: return "BYE"
        case .cont: return "CONT"
        case .com: return "COM"
        case .close: return "CLOSE"
        case .clr: return "CLR"
        case .deg: return "DEG"
        case .dim: return "DIM"
        case .end: return "END"
        case .new: return "NEW"
        case .open: return "OPEN"
        case .load: return "LOAD"
        case .save: return "SAVE"
        case .status: return "STATUS"
        case .note: return "NOTE"
        case .point: return "POINT"
        case .xio: return "XIO"
        case .on: return "ON"
        case .poke: return "POKE"
        case .print: return "PRINT"
        case .rad: return "RAD"
        case .read: return "READ"
        case .restore: return "RESTORE"
        case .returnStatement: return "RETURN"
        case .run: return "RUN"
        case .stop: return "STOP"
        case .pop: return "POP"
        case .printShort: return "?"
        case .get: return "GET"
        case .put: return "PUT"
        case .graphics: return "GRAPHICS"
        case .plot: return "PLOT"
        case .position: return "POSITION"
        case .dos: return "DOS"
        case .drawto: return "DRAWTO"
        case .setcolor: return "SETCOLOR"
        case .locate: return "LOCATE"
        case .sound: return "SOUND"
        case .lprint: return "LPRINT"
        case .csave: return "CSAVE"
        case .cload: return "CLOAD"
        case .impliedLet: return ""  // No keyword, just assignment
        }
    }
}

// =============================================================================
// MARK: - Operator Tokens ($37-$5C)
// =============================================================================

/// Operator tokens represent punctuation, arithmetic, comparison, and logical operators.
///
/// These tokens appear within the EXPRESSION portion of tokenized lines (after
/// the statement name token). Their byte values ($12-$37) overlap with statement
/// token values ($00-$36) — the Atari BASIC ROM uses position context to
/// disambiguate: the first byte after the header (and after each colon separator)
/// is a statement name, while all other bytes use the expression token space.
///
/// Note that some operators have different tokens depending on context
/// (e.g., assignment = vs comparison =).
///
/// Reference: De Re Atari Chapter 10, Atari BASIC Source Book
public enum BASICOperatorToken: UInt8, CaseIterable, Sendable {
    case comma = 0x12             // ,
    case dollarSign = 0x13        // $ (string type indicator)
    case colon = 0x14             // : (statement separator)
    case semicolon = 0x15         // ;
    case endOfLine = 0x16         // EOL marker
    case gotoInOn = 0x17          // GOTO within ON...GOTO
    case gosubInOn = 0x18         // GOSUB within ON...GOSUB
    case toKeyword = 0x19         // TO (in FOR...TO)
    case step = 0x1A              // STEP (in FOR...STEP)
    case then = 0x1B              // THEN (in IF...THEN)
    case pound = 0x1C             // # (channel number prefix)
    case lessEqual = 0x1D         // <=
    case notEqual = 0x1E          // <>
    case greaterEqual = 0x1F      // >=
    case lessThan = 0x20          // <
    case greaterThan = 0x21       // >
    case equals = 0x22            // = (in expressions)
    case power = 0x23             // ^
    case multiply = 0x24          // *
    case plus = 0x25              // +
    case minus = 0x26             // -
    case divide = 0x27            // /
    case not = 0x28               // NOT
    case or = 0x29                // OR
    case and = 0x2A               // AND
    case leftParen = 0x2B         // (
    case rightParen = 0x2C        // )
    case equalsAssign = 0x2D      // = (assignment)
    case equalsCompare = 0x2E     // = (comparison, alternate)
    case lessEqual2 = 0x2F        // <= (alternate)
    case notEqual2 = 0x30         // <> (alternate)
    case greaterEqual2 = 0x31     // >= (alternate)
    case lessThan2 = 0x32         // < (alternate)
    case greaterThan2 = 0x33      // > (alternate)
    case equals2 = 0x34           // = (alternate)
    case unaryPlus = 0x35         // + (unary)
    case unaryMinus = 0x36        // - (unary)
    case leftParenArray = 0x37    // ( (array subscript)

    /// The string representation of this operator.
    public var symbol: String {
        switch self {
        case .comma: return ","
        case .dollarSign: return "$"
        case .colon: return ":"
        case .semicolon: return ";"
        case .endOfLine: return ""
        case .gotoInOn: return "GOTO"
        case .gosubInOn: return "GOSUB"
        case .toKeyword: return "TO"
        case .step: return "STEP"
        case .then: return "THEN"
        case .pound: return "#"
        case .lessEqual, .lessEqual2: return "<="
        case .notEqual, .notEqual2: return "<>"
        case .greaterEqual, .greaterEqual2: return ">="
        case .lessThan, .lessThan2: return "<"
        case .greaterThan, .greaterThan2: return ">"
        case .equals, .equalsAssign, .equalsCompare, .equals2: return "="
        case .power: return "^"
        case .multiply: return "*"
        case .plus, .unaryPlus: return "+"
        case .minus, .unaryMinus: return "-"
        case .divide: return "/"
        case .not: return "NOT"
        case .or: return "OR"
        case .and: return "AND"
        case .leftParen, .leftParenArray: return "("
        case .rightParen: return ")"
        }
    }
}

// =============================================================================
// MARK: - Function Tokens ($5D-$74)
// =============================================================================

/// Function tokens represent built-in BASIC functions.
///
/// Like operator tokens, these appear in the EXPRESSION portion of tokenized
/// lines (after the statement name token). Their byte values ($38-$4F) do not
/// overlap with statement tokens ($00-$36) or operator tokens ($12-$37).
///
/// Functions are used within expressions and always have parentheses
/// following them (even if empty, like RND).
///
/// Reference: De Re Atari Chapter 10, Atari BASIC Source Book
public enum BASICFunctionToken: UInt8, CaseIterable, Sendable {
    case str = 0x38               // STR$
    case chr = 0x39               // CHR$
    case usr = 0x3A               // USR
    case asc = 0x3B               // ASC
    case val = 0x3C               // VAL
    case len = 0x3D               // LEN
    case adr = 0x3E               // ADR
    case atn = 0x3F               // ATN
    case cos = 0x40               // COS
    case peek = 0x41              // PEEK
    case sin = 0x42               // SIN
    case rnd = 0x43               // RND
    case fre = 0x44               // FRE
    case exp = 0x45               // EXP
    case log = 0x46               // LOG
    case clog = 0x47              // CLOG
    case sqr = 0x48               // SQR
    case sgn = 0x49               // SGN
    case abs = 0x4A               // ABS
    case int = 0x4B               // INT
    case paddle = 0x4C            // PADDLE
    case stick = 0x4D             // STICK
    case ptrig = 0x4E             // PTRIG
    case strig = 0x4F             // STRIG

    /// The keyword string for this function.
    public var keyword: String {
        switch self {
        case .str: return "STR$"
        case .chr: return "CHR$"
        case .usr: return "USR"
        case .asc: return "ASC"
        case .val: return "VAL"
        case .len: return "LEN"
        case .adr: return "ADR"
        case .atn: return "ATN"
        case .cos: return "COS"
        case .peek: return "PEEK"
        case .sin: return "SIN"
        case .rnd: return "RND"
        case .fre: return "FRE"
        case .exp: return "EXP"
        case .log: return "LOG"
        case .clog: return "CLOG"
        case .sqr: return "SQR"
        case .sgn: return "SGN"
        case .abs: return "ABS"
        case .int: return "INT"
        case .paddle: return "PADDLE"
        case .stick: return "STICK"
        case .ptrig: return "PTRIG"
        case .strig: return "STRIG"
        }
    }
}

// =============================================================================
// MARK: - Special Token Constants
// =============================================================================

/// Special byte values used in tokenized BASIC programs.
public enum BASICSpecialToken {
    /// Small integer constant prefix (followed by 1 byte value 0-255).
    public static let smallIntPrefix: UInt8 = 0x0D

    /// BCD floating-point constant prefix (followed by 6 bytes).
    public static let bcdFloatPrefix: UInt8 = 0x0E

    /// String constant prefix (followed by length byte and characters).
    public static let stringPrefix: UInt8 = 0x0F

    /// End of line marker.
    public static let endOfLine: UInt8 = 0x16

    /// Variable reference base (add variable index to get token).
    /// First variable is $80, second is $81, etc.
    public static let variableBase: UInt8 = 0x80

    /// Maximum variable index (128 variables: $80-$FF).
    public static let maxVariableIndex: UInt8 = 127
}

// =============================================================================
// MARK: - Token Lookup Tables
// =============================================================================

/// Provides lookup tables for converting between keywords and tokens.
///
/// This enum contains static methods and dictionaries for efficient
/// keyword-to-token and token-to-keyword conversion.
public enum BASICTokenLookup {

    // =========================================================================
    // MARK: - Statement Lookup
    // =========================================================================

    /// Maps uppercase keywords to statement tokens.
    ///
    /// Includes both standard keywords and common abbreviations.
    public static let statementKeywords: [String: BASICStatementToken] = {
        var dict: [String: BASICStatementToken] = [:]
        for token in BASICStatementToken.allCases {
            if !token.keyword.isEmpty {
                dict[token.keyword] = token
            }
        }
        // Add "GO TO" variant (handled specially during lexing)
        return dict
    }()

    /// Attempts to match a keyword (or abbreviation) to a statement token.
    ///
    /// Atari BASIC allows keywords to be abbreviated with a period.
    /// For example, "PR." matches "PRINT", "G." matches "GOTO".
    ///
    /// - Parameter keyword: The keyword to look up (case-insensitive).
    /// - Returns: The matching token, or nil if not found.
    public static func matchStatement(_ keyword: String) -> BASICStatementToken? {
        let upper = keyword.uppercased()

        // Check for exact match first
        if let token = statementKeywords[upper] {
            return token
        }

        // Check for abbreviation (ends with period)
        if upper.hasSuffix(".") {
            let prefix = String(upper.dropLast())
            // Find first keyword that starts with this prefix
            for token in BASICStatementToken.allCases {
                if token.keyword.hasPrefix(prefix) && !token.keyword.isEmpty {
                    return token
                }
            }
        }

        // Special case: "?" is PRINT
        if upper == "?" {
            return .printShort
        }

        return nil
    }

    // =========================================================================
    // MARK: - Function Lookup
    // =========================================================================

    /// Maps uppercase keywords to function tokens.
    public static let functionKeywords: [String: BASICFunctionToken] = {
        var dict: [String: BASICFunctionToken] = [:]
        for token in BASICFunctionToken.allCases {
            dict[token.keyword] = token
        }
        return dict
    }()

    /// Attempts to match a keyword to a function token.
    ///
    /// - Parameter keyword: The keyword to look up (case-insensitive).
    /// - Returns: The matching token, or nil if not found.
    public static func matchFunction(_ keyword: String) -> BASICFunctionToken? {
        let upper = keyword.uppercased()

        // Check for exact match
        if let token = functionKeywords[upper] {
            return token
        }

        // Check for abbreviation
        if upper.hasSuffix(".") {
            let prefix = String(upper.dropLast())
            for token in BASICFunctionToken.allCases {
                if token.keyword.hasPrefix(prefix) {
                    return token
                }
            }
        }

        return nil
    }

    // =========================================================================
    // MARK: - Operator Lookup
    // =========================================================================

    /// Maps operator strings to operator tokens.
    ///
    /// Note: Some operators have context-dependent tokens (e.g., = for
    /// assignment vs comparison). This table provides the default token.
    public static let operatorSymbols: [String: BASICOperatorToken] = [
        ",": .comma,
        ":": .colon,
        ";": .semicolon,
        "#": .pound,
        "<=": .lessEqual,
        "=<": .lessEqual,     // Alternate form
        "<>": .notEqual,
        "><": .notEqual,      // Alternate form
        ">=": .greaterEqual,
        "=>": .greaterEqual,  // Alternate form
        "<": .lessThan,
        ">": .greaterThan,
        "=": .equals,
        "^": .power,
        "*": .multiply,
        "+": .plus,
        "-": .minus,
        "/": .divide,
        "(": .leftParen,
        ")": .rightParen,
    ]

    /// Maps logical operator keywords to tokens.
    public static let logicalOperators: [String: BASICOperatorToken] = [
        "NOT": .not,
        "OR": .or,
        "AND": .and,
        "TO": .toKeyword,
        "STEP": .step,
        "THEN": .then,
    ]

    /// Attempts to match a symbol to an operator token.
    ///
    /// - Parameter symbol: The operator symbol to look up.
    /// - Returns: The matching token, or nil if not found.
    public static func matchOperator(_ symbol: String) -> BASICOperatorToken? {
        if let token = operatorSymbols[symbol] {
            return token
        }
        return logicalOperators[symbol.uppercased()]
    }

    // =========================================================================
    // MARK: - Keyword Detection
    // =========================================================================

    /// Checks if a string is any BASIC keyword (statement, function, or operator).
    ///
    /// - Parameter word: The word to check (case-insensitive).
    /// - Returns: True if the word is a reserved keyword.
    public static func isKeyword(_ word: String) -> Bool {
        let upper = word.uppercased()
        return statementKeywords[upper] != nil ||
               functionKeywords[upper] != nil ||
               logicalOperators[upper] != nil
    }

    /// Finds the closest keyword to a misspelled word (for error suggestions).
    ///
    /// Uses Levenshtein distance to find the keyword with the smallest edit
    /// distance to the input. Returns the best match if within threshold.
    ///
    /// - Parameter word: The misspelled word.
    /// - Returns: A suggested correction, or nil if no close match found.
    public static func suggestKeyword(_ word: String) -> String? {
        let upper = word.uppercased()
        var bestMatch: String?
        var bestDistance = Int.max

        // Check statement keywords
        for token in BASICStatementToken.allCases {
            let kw = token.keyword
            guard !kw.isEmpty else { continue }

            let distance = levenshteinDistance(upper, kw)
            if distance < bestDistance {
                bestDistance = distance
                bestMatch = kw
            }
        }

        // Check function keywords
        for token in BASICFunctionToken.allCases {
            let kw = token.keyword
            let distance = levenshteinDistance(upper, kw)
            if distance < bestDistance {
                bestDistance = distance
                bestMatch = kw
            }
        }

        // Only return if within reasonable threshold (2 edits)
        return bestDistance <= 2 ? bestMatch : nil
    }

    /// Calculates the Levenshtein distance between two strings.
    ///
    /// This is used for fuzzy matching to suggest corrections for typos.
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // Deletion
                    matrix[i][j - 1] + 1,      // Insertion
                    matrix[i - 1][j - 1] + cost // Substitution
                )
            }
        }

        return matrix[m][n]
    }
}
