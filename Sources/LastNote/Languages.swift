import Foundation
import SciKit

/// A language = a Lexilla lexer + keyword lists + a mapping from the lexer's style numbers
/// to theme tokens.
struct Language {
    let name: String
    let lexer: String
    var extensions: [String] = []
    var filenames: [String] = []
    var keywords: [String] = []
    var styles: [Int32: Token] = [:]
    var properties: [String: String] = [:]
    /// Line-comment prefix for "Toggle Comment".
    var lineComment: String? = nil

    static let plainText = Language(name: "Normal text", lexer: "null")

    static func detect(url: URL?, firstLine: String) -> Language {
        if let url {
            let file = url.lastPathComponent.lowercased()
            if let l = all.first(where: { $0.filenames.contains(file) }) { return l }
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty, let l = all.first(where: { $0.extensions.contains(ext) }) { return l }
        }
        if firstLine.hasPrefix("#!") {
            let line = firstLine.lowercased()
            let byShebang: [(String, String)] = [
                ("python", "Python"), ("node", "JavaScript"), ("ruby", "Ruby"), ("lua", "Lua"),
                ("pwsh", "PowerShell"), ("bash", "Shell"), ("zsh", "Shell"), ("sh", "Shell"),
            ]
            for (needle, name) in byShebang where line.contains(needle) {
                if let l = all.first(where: { $0.name == name }) { return l }
            }
        }
        if firstLine.hasPrefix("<?xml") { return all.first { $0.name == "XML" }! }
        return .plainText
    }

    static let all: [Language] = [
        cFamily("C", ["c", "h"], cKeywords, "size_t ssize_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t FILE NULL"),
        cFamily("C++", ["cpp", "cc", "cxx", "hpp", "hh", "hxx", "ino", "mm", "m"], cppKeywords, "std string vector map unordered_map set array unique_ptr shared_ptr size_t nullptr_t"),
        cFamily("C#", ["cs"], csKeywords, "Console List Dictionary Task String Int32 Int64 Exception"),
        cFamily("Java", ["java"], javaKeywords, "String Integer Long Object List Map ArrayList HashMap Exception System"),
        cFamily("JavaScript", ["js", "mjs", "cjs", "jsx"], jsKeywords, "console window document JSON Math Promise Array Object String Number Map Set Error"),
        cFamily("TypeScript", ["ts", "tsx", "mts", "cts"], jsKeywords + " " + tsKeywords, "console window document JSON Math Promise Array Object String Number Map Set Error Record Partial"),
        cFamily("Swift", ["swift"], swiftKeywords, "Int Double Float String Bool Array Dictionary Set Optional Character Void Any AnyObject Self"),
        cFamily("Go", ["go"], goKeywords, "bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr"),
        cFamily("Kotlin", ["kt", "kts"], kotlinKeywords, "Int Long Double Float String Boolean Unit Any List Map Set Array"),
        Language(
            name: "Python", lexer: "python", extensions: ["py", "pyw", "pyi"],
            keywords: [
                "False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case",
                "self cls print len range int str float bool list dict set tuple open type isinstance enumerate zip map filter sorted sum min max abs any all super object Exception",
            ],
            styles: [
                Int32(SCE_P_DEFAULT): .plain, Int32(SCE_P_COMMENTLINE): .comment, Int32(SCE_P_COMMENTBLOCK): .comment,
                Int32(SCE_P_NUMBER): .number, Int32(SCE_P_STRING): .string, Int32(SCE_P_CHARACTER): .string,
                Int32(SCE_P_TRIPLE): .docComment, Int32(SCE_P_TRIPLEDOUBLE): .docComment,
                Int32(SCE_P_FSTRING): .string, Int32(SCE_P_FCHARACTER): .string, Int32(SCE_P_FTRIPLE): .string, Int32(SCE_P_FTRIPLEDOUBLE): .string,
                Int32(SCE_P_WORD): .keyword, Int32(SCE_P_WORD2): .keyword2, Int32(SCE_P_CLASSNAME): .type,
                Int32(SCE_P_DEFNAME): .function, Int32(SCE_P_OPERATOR): .op, Int32(SCE_P_DECORATOR): .preprocessor,
                Int32(SCE_P_ATTRIBUTE): .attribute, Int32(SCE_P_STRINGEOL): .error,
            ],
            properties: ["fold.quotes.python": "1"],
            lineComment: "#"),
        Language(
            name: "SQL", lexer: "sql", extensions: ["sql", "pls", "plsql", "pks", "pkb", "prc", "fnc", "trg", "vw", "ddl", "dml"],
            keywords: [sqlKeywords, sqlFunctions],
            styles: [
                Int32(SCE_SQL_DEFAULT): .plain, Int32(SCE_SQL_COMMENT): .comment, Int32(SCE_SQL_COMMENTLINE): .comment,
                Int32(SCE_SQL_COMMENTDOC): .docComment, Int32(SCE_SQL_COMMENTLINEDOC): .docComment,
                Int32(SCE_SQL_NUMBER): .number, Int32(SCE_SQL_WORD): .keyword, Int32(SCE_SQL_WORD2): .function,
                Int32(SCE_SQL_STRING): .string, Int32(SCE_SQL_CHARACTER): .string, Int32(SCE_SQL_QOPERATOR): .string,
                Int32(SCE_SQL_OPERATOR): .op, Int32(SCE_SQL_QUOTEDIDENTIFIER): .variable,
                Int32(SCE_SQL_SQLPLUS): .preprocessor, Int32(SCE_SQL_SQLPLUS_PROMPT): .preprocessor, Int32(SCE_SQL_SQLPLUS_COMMENT): .comment,
            ],
            properties: ["sql.backslash.escapes": "0", "lexer.sql.numbersign.comment": "0"],
            lineComment: "--"),
        Language(
            name: "Shell", lexer: "bash", extensions: ["sh", "bash", "zsh", "command", "ksh"],
            filenames: [".bashrc", ".zshrc", ".bash_profile", ".zprofile", ".profile"],
            keywords: ["if then else elif fi case esac for while until do done in function select time return exit break continue local export readonly declare typeset unset source alias echo printf read cd pwd test shift eval exec set trap wait"],
            styles: [
                Int32(SCE_SH_DEFAULT): .plain, Int32(SCE_SH_COMMENTLINE): .comment, Int32(SCE_SH_NUMBER): .number,
                Int32(SCE_SH_WORD): .keyword, Int32(SCE_SH_STRING): .string, Int32(SCE_SH_CHARACTER): .string,
                Int32(SCE_SH_OPERATOR): .op, Int32(SCE_SH_SCALAR): .variable, Int32(SCE_SH_PARAM): .variable,
                Int32(SCE_SH_BACKTICKS): .keyword2, Int32(SCE_SH_HERE_DELIM): .preprocessor, Int32(SCE_SH_HERE_Q): .string,
                Int32(SCE_SH_ERROR): .error,
            ],
            lineComment: "#"),
        Language(
            name: "JSON", lexer: "json", extensions: ["json", "jsonc", "json5", "geojson", "webmanifest"],
            keywords: ["true false null"],
            styles: [
                Int32(SCE_JSON_DEFAULT): .plain, Int32(SCE_JSON_NUMBER): .number, Int32(SCE_JSON_STRING): .string,
                Int32(SCE_JSON_PROPERTYNAME): .attribute, Int32(SCE_JSON_ESCAPESEQUENCE): .keyword2,
                Int32(SCE_JSON_LINECOMMENT): .comment, Int32(SCE_JSON_BLOCKCOMMENT): .comment,
                Int32(SCE_JSON_OPERATOR): .op, Int32(SCE_JSON_KEYWORD): .keyword, Int32(SCE_JSON_URI): .string,
                Int32(SCE_JSON_ERROR): .error, Int32(SCE_JSON_STRINGEOL): .error,
            ],
            properties: ["lexer.json.allow.comments": "1", "lexer.json.escape.sequence": "1"]),
        Language(
            name: "HTML", lexer: "hypertext", extensions: ["html", "htm", "xhtml", "vue", "svelte"],
            keywords: [htmlKeywords, jsKeywords],
            styles: htmlStyles,
            properties: ["fold.html": "1"]),
        Language(
            name: "XML", lexer: "xml", extensions: ["xml", "xsd", "xsl", "xslt", "plist", "svg", "wsdl", "pom", "csproj", "storyboard", "xib"],
            styles: htmlStyles,
            properties: ["fold.html": "1"]),
        Language(
            name: "CSS", lexer: "css", extensions: ["css", "scss", "less"],
            keywords: ["color background background-color border margin padding width height display position top left right bottom font font-size font-weight font-family line-height text-align flex grid gap align-items justify-content overflow opacity z-index transform transition animation cursor box-shadow border-radius content"],
            styles: [
                Int32(SCE_CSS_DEFAULT): .plain, Int32(SCE_CSS_TAG): .tag, Int32(SCE_CSS_CLASS): .type, Int32(SCE_CSS_ID): .type,
                Int32(SCE_CSS_PSEUDOCLASS): .keyword2, Int32(SCE_CSS_PSEUDOELEMENT): .keyword2,
                Int32(SCE_CSS_IDENTIFIER): .attribute, Int32(SCE_CSS_IDENTIFIER2): .attribute, Int32(SCE_CSS_IDENTIFIER3): .attribute,
                Int32(SCE_CSS_UNKNOWN_IDENTIFIER): .attribute, Int32(SCE_CSS_VALUE): .string,
                Int32(SCE_CSS_COMMENT): .comment, Int32(SCE_CSS_OPERATOR): .op, Int32(SCE_CSS_IMPORTANT): .keyword,
                Int32(SCE_CSS_DIRECTIVE): .preprocessor, Int32(SCE_CSS_DOUBLESTRING): .string, Int32(SCE_CSS_SINGLESTRING): .string,
                Int32(SCE_CSS_VARIABLE): .variable, Int32(SCE_CSS_GROUP_RULE): .preprocessor,
            ]),
        Language(
            name: "Markdown", lexer: "markdown", extensions: ["md", "markdown", "mdown", "mkd"],
            styles: [
                Int32(SCE_MARKDOWN_DEFAULT): .plain, Int32(SCE_MARKDOWN_STRONG1): .keyword, Int32(SCE_MARKDOWN_STRONG2): .keyword,
                Int32(SCE_MARKDOWN_EM1): .emphasis, Int32(SCE_MARKDOWN_EM2): .emphasis,
                Int32(SCE_MARKDOWN_HEADER1): .heading, Int32(SCE_MARKDOWN_HEADER2): .heading, Int32(SCE_MARKDOWN_HEADER3): .heading,
                Int32(SCE_MARKDOWN_HEADER4): .heading, Int32(SCE_MARKDOWN_HEADER5): .heading, Int32(SCE_MARKDOWN_HEADER6): .heading,
                Int32(SCE_MARKDOWN_PRECHAR): .op, Int32(SCE_MARKDOWN_ULIST_ITEM): .keyword2, Int32(SCE_MARKDOWN_OLIST_ITEM): .keyword2,
                Int32(SCE_MARKDOWN_BLOCKQUOTE): .comment, Int32(SCE_MARKDOWN_STRIKEOUT): .comment, Int32(SCE_MARKDOWN_HRULE): .op,
                Int32(SCE_MARKDOWN_LINK): .attribute, Int32(SCE_MARKDOWN_CODE): .string, Int32(SCE_MARKDOWN_CODE2): .string,
                Int32(SCE_MARKDOWN_CODEBK): .string,
            ]),
        Language(
            name: "YAML", lexer: "yaml", extensions: ["yml", "yaml"],
            keywords: ["true false yes no null on off"],
            styles: [
                Int32(SCE_YAML_DEFAULT): .plain, Int32(SCE_YAML_COMMENT): .comment, Int32(SCE_YAML_IDENTIFIER): .attribute,
                Int32(SCE_YAML_KEYWORD): .keyword, Int32(SCE_YAML_NUMBER): .number, Int32(SCE_YAML_REFERENCE): .variable,
                Int32(SCE_YAML_DOCUMENT): .preprocessor, Int32(SCE_YAML_TEXT): .string, Int32(SCE_YAML_ERROR): .error,
                Int32(SCE_YAML_OPERATOR): .op,
            ],
            lineComment: "#"),
        Language(
            name: "TOML", lexer: "toml", extensions: ["toml"],
            keywords: ["true false"],
            styles: [
                Int32(SCE_TOML_DEFAULT): .plain, Int32(SCE_TOML_COMMENT): .comment, Int32(SCE_TOML_IDENTIFIER): .plain,
                Int32(SCE_TOML_KEYWORD): .keyword, Int32(SCE_TOML_NUMBER): .number, Int32(SCE_TOML_TABLE): .heading,
                Int32(SCE_TOML_KEY): .attribute, Int32(SCE_TOML_ERROR): .error, Int32(SCE_TOML_OPERATOR): .op,
                Int32(SCE_TOML_STRING_SQ): .string, Int32(SCE_TOML_STRING_DQ): .string,
                Int32(SCE_TOML_TRIPLE_STRING_SQ): .string, Int32(SCE_TOML_TRIPLE_STRING_DQ): .string,
                Int32(SCE_TOML_ESCAPECHAR): .keyword2, Int32(SCE_TOML_DATETIME): .number,
            ],
            lineComment: "#"),
        Language(
            name: "INI / Properties", lexer: "props", extensions: ["ini", "cfg", "conf", "properties", "env", "gitconfig", "editorconfig"],
            filenames: [".env", ".gitconfig", ".editorconfig", ".npmrc"],
            styles: [
                Int32(SCE_PROPS_DEFAULT): .plain, Int32(SCE_PROPS_COMMENT): .comment, Int32(SCE_PROPS_SECTION): .heading,
                Int32(SCE_PROPS_ASSIGNMENT): .op, Int32(SCE_PROPS_DEFVAL): .string, Int32(SCE_PROPS_KEY): .attribute,
            ],
            lineComment: "#"),
        Language(
            name: "Makefile", lexer: "makefile", extensions: ["mk", "mak"], filenames: ["makefile", "gnumakefile"],
            styles: [
                Int32(SCE_MAKE_DEFAULT): .plain, Int32(SCE_MAKE_COMMENT): .comment, Int32(SCE_MAKE_PREPROCESSOR): .preprocessor,
                Int32(SCE_MAKE_IDENTIFIER): .variable, Int32(SCE_MAKE_OPERATOR): .op, Int32(SCE_MAKE_TARGET): .function,
                Int32(SCE_MAKE_IDEOL): .error,
            ],
            lineComment: "#"),
        Language(
            name: "Rust", lexer: "rust", extensions: ["rs"],
            keywords: [
                "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while",
                "bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 usize String Vec Option Result Box Some None Ok Err",
            ],
            styles: [
                Int32(SCE_RUST_DEFAULT): .plain, Int32(SCE_RUST_COMMENTBLOCK): .comment, Int32(SCE_RUST_COMMENTLINE): .comment,
                Int32(SCE_RUST_COMMENTBLOCKDOC): .docComment, Int32(SCE_RUST_COMMENTLINEDOC): .docComment,
                Int32(SCE_RUST_NUMBER): .number, Int32(SCE_RUST_WORD): .keyword, Int32(SCE_RUST_WORD2): .type,
                Int32(SCE_RUST_STRING): .string, Int32(SCE_RUST_STRINGR): .string, Int32(SCE_RUST_CHARACTER): .string,
                Int32(SCE_RUST_BYTESTRING): .string, Int32(SCE_RUST_BYTESTRINGR): .string, Int32(SCE_RUST_BYTECHARACTER): .string,
                Int32(SCE_RUST_CSTRING): .string, Int32(SCE_RUST_CSTRINGR): .string,
                Int32(SCE_RUST_OPERATOR): .op, Int32(SCE_RUST_MACRO): .preprocessor, Int32(SCE_RUST_LIFETIME): .keyword2,
                Int32(SCE_RUST_LEXERROR): .error,
            ],
            lineComment: "//"),
        Language(
            name: "Lua", lexer: "lua", extensions: ["lua"],
            keywords: ["and break do else elseif end false for function goto if in local nil not or repeat return then true until while",
                       "print pairs ipairs type tostring tonumber require setmetatable getmetatable table string math os io"],
            styles: [
                Int32(SCE_LUA_DEFAULT): .plain, Int32(SCE_LUA_COMMENT): .comment, Int32(SCE_LUA_COMMENTLINE): .comment,
                Int32(SCE_LUA_COMMENTDOC): .docComment, Int32(SCE_LUA_NUMBER): .number, Int32(SCE_LUA_WORD): .keyword,
                Int32(SCE_LUA_WORD2): .function, Int32(SCE_LUA_STRING): .string, Int32(SCE_LUA_CHARACTER): .string,
                Int32(SCE_LUA_LITERALSTRING): .string, Int32(SCE_LUA_OPERATOR): .op, Int32(SCE_LUA_PREPROCESSOR): .preprocessor,
                Int32(SCE_LUA_LABEL): .preprocessor, Int32(SCE_LUA_STRINGEOL): .error,
            ],
            lineComment: "--"),
        Language(
            name: "Ruby", lexer: "ruby", extensions: ["rb", "rake", "gemspec"], filenames: ["gemfile", "rakefile", "podfile"],
            keywords: ["__FILE__ __LINE__ BEGIN END alias and begin break case class def defined? do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require attr_accessor attr_reader puts"],
            styles: [
                Int32(SCE_RB_DEFAULT): .plain, Int32(SCE_RB_COMMENTLINE): .comment, Int32(SCE_RB_POD): .docComment,
                Int32(SCE_RB_NUMBER): .number, Int32(SCE_RB_WORD): .keyword, Int32(SCE_RB_STRING): .string,
                Int32(SCE_RB_CHARACTER): .string, Int32(SCE_RB_CLASSNAME): .type, Int32(SCE_RB_DEFNAME): .function,
                Int32(SCE_RB_OPERATOR): .op, Int32(SCE_RB_REGEX): .regex, Int32(SCE_RB_GLOBAL): .variable,
                Int32(SCE_RB_SYMBOL): .keyword2, Int32(SCE_RB_MODULE_NAME): .type, Int32(SCE_RB_INSTANCE_VAR): .variable,
                Int32(SCE_RB_CLASS_VAR): .variable, Int32(SCE_RB_ERROR): .error,
            ],
            lineComment: "#"),
        Language(
            name: "PowerShell", lexer: "powershell", extensions: ["ps1", "psm1", "psd1"],
            keywords: ["begin break catch class continue data default do dynamicparam else elseif end exit filter finally for foreach from function if in param process return switch throw trap try until using var while"],
            styles: [
                Int32(SCE_POWERSHELL_DEFAULT): .plain, Int32(SCE_POWERSHELL_COMMENT): .comment, Int32(SCE_POWERSHELL_COMMENTSTREAM): .comment,
                Int32(SCE_POWERSHELL_STRING): .string, Int32(SCE_POWERSHELL_CHARACTER): .string, Int32(SCE_POWERSHELL_NUMBER): .number,
                Int32(SCE_POWERSHELL_VARIABLE): .variable, Int32(SCE_POWERSHELL_OPERATOR): .op, Int32(SCE_POWERSHELL_KEYWORD): .keyword,
                Int32(SCE_POWERSHELL_CMDLET): .function, Int32(SCE_POWERSHELL_ALIAS): .function, Int32(SCE_POWERSHELL_FUNCTION): .function,
                Int32(SCE_POWERSHELL_HERE_STRING): .string, Int32(SCE_POWERSHELL_HERE_CHARACTER): .string,
            ],
            lineComment: "#"),
        Language(
            name: "Batch", lexer: "batch", extensions: ["bat", "cmd"],
            keywords: ["rem set if exist errorlevel for in do break call copy chcp cd chdir choice cls country ctty date del erase dir echo exit goto loadfix loadhigh mkdir md move path pause prompt rename ren rmdir rd shift time type ver verify vol not else setlocal endlocal"],
            styles: [
                Int32(SCE_BAT_DEFAULT): .plain, Int32(SCE_BAT_COMMENT): .comment, Int32(SCE_BAT_WORD): .keyword,
                Int32(SCE_BAT_LABEL): .function, Int32(SCE_BAT_HIDE): .preprocessor, Int32(SCE_BAT_COMMAND): .keyword2,
                Int32(SCE_BAT_IDENTIFIER): .variable, Int32(SCE_BAT_OPERATOR): .op,
            ],
            lineComment: "REM "),
        Language(
            name: "Diff", lexer: "diff", extensions: ["diff", "patch"],
            styles: [
                Int32(SCE_DIFF_DEFAULT): .plain, Int32(SCE_DIFF_COMMENT): .comment, Int32(SCE_DIFF_COMMAND): .keyword,
                Int32(SCE_DIFF_HEADER): .heading, Int32(SCE_DIFF_POSITION): .keyword2, Int32(SCE_DIFF_DELETED): .removed,
                Int32(SCE_DIFF_ADDED): .added, Int32(SCE_DIFF_CHANGED): .emphasis,
            ]),
    ]

    private static func cFamily(_ name: String, _ exts: [String], _ kw: String, _ types: String) -> Language {
        Language(
            name: name, lexer: "cpp", extensions: exts,
            keywords: [kw, types],
            styles: [
                Int32(SCE_C_DEFAULT): .plain, Int32(SCE_C_COMMENT): .comment, Int32(SCE_C_COMMENTLINE): .comment,
                Int32(SCE_C_COMMENTDOC): .docComment, Int32(SCE_C_COMMENTLINEDOC): .docComment,
                Int32(SCE_C_COMMENTDOCKEYWORD): .docComment, Int32(SCE_C_COMMENTDOCKEYWORDERROR): .error,
                Int32(SCE_C_NUMBER): .number, Int32(SCE_C_WORD): .keyword, Int32(SCE_C_WORD2): .type,
                Int32(SCE_C_STRING): .string, Int32(SCE_C_CHARACTER): .string, Int32(SCE_C_STRINGRAW): .string,
                Int32(SCE_C_VERBATIM): .string, Int32(SCE_C_TRIPLEVERBATIM): .string, Int32(SCE_C_HASHQUOTEDSTRING): .string,
                Int32(SCE_C_UUID): .number, Int32(SCE_C_OPERATOR): .op, Int32(SCE_C_PREPROCESSOR): .preprocessor,
                Int32(SCE_C_REGEX): .regex, Int32(SCE_C_GLOBALCLASS): .type, Int32(SCE_C_STRINGEOL): .error,
                Int32(SCE_C_ESCAPESEQUENCE): .keyword2, Int32(SCE_C_TASKMARKER): .emphasis, Int32(SCE_C_USERLITERAL): .number,
            ],
            properties: ["lexer.cpp.track.preprocessor": "0", "lexer.cpp.backquoted.strings": "1", "fold.preprocessor": "1"],
            lineComment: "//")
    }

    private static let htmlStyles: [Int32: Token] = [
        Int32(SCE_H_DEFAULT): .plain, Int32(SCE_H_TAG): .tag, Int32(SCE_H_TAGUNKNOWN): .tag, Int32(SCE_H_TAGEND): .tag,
        Int32(SCE_H_ATTRIBUTE): .attribute, Int32(SCE_H_ATTRIBUTEUNKNOWN): .attribute, Int32(SCE_H_NUMBER): .number,
        Int32(SCE_H_DOUBLESTRING): .string, Int32(SCE_H_SINGLESTRING): .string, Int32(SCE_H_VALUE): .string,
        Int32(SCE_H_OTHER): .op, Int32(SCE_H_COMMENT): .comment, Int32(SCE_H_ENTITY): .keyword2,
        Int32(SCE_H_XMLSTART): .preprocessor, Int32(SCE_H_XMLEND): .preprocessor, Int32(SCE_H_CDATA): .string,
        Int32(SCE_H_SGML_DEFAULT): .preprocessor, Int32(SCE_H_SGML_COMMAND): .preprocessor,
        Int32(SCE_HJ_DEFAULT): .plain, Int32(SCE_HJ_COMMENT): .comment, Int32(SCE_HJ_COMMENTLINE): .comment,
        Int32(SCE_HJ_COMMENTDOC): .docComment, Int32(SCE_HJ_NUMBER): .number, Int32(SCE_HJ_WORD): .plain,
        Int32(SCE_HJ_KEYWORD): .keyword, Int32(SCE_HJ_DOUBLESTRING): .string, Int32(SCE_HJ_SINGLESTRING): .string,
        Int32(SCE_HJ_TEMPLATELITERAL): .string, Int32(SCE_HJ_SYMBOLS): .op, Int32(SCE_HJ_REGEX): .regex,
        Int32(SCE_HJ_STRINGEOL): .error,
    ]
}

// MARK: - Keyword lists

private let cKeywords = "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while _Bool _Complex _Atomic _Noreturn _Static_assert bool true false"
private let cppKeywords = cKeywords + " alignas alignof and asm catch char8_t char16_t char32_t class concept consteval constexpr constinit const_cast co_await co_return co_yield decltype delete dynamic_cast explicit export friend mutable namespace new noexcept not nullptr operator or override final private protected public reinterpret_cast requires static_assert static_cast template this thread_local throw try typeid typename using virtual wchar_t"
private let csKeywords = "abstract as async await base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly record ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using var virtual void volatile while yield get set init value"
private let javaKeywords = "abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false null var record sealed permits yield"
private let jsKeywords = "async await break case catch class const continue debugger default delete do else export extends false finally for from function get if import in instanceof let new null of return set static super switch this throw true try typeof undefined var void while with yield"
private let tsKeywords = "abstract any as asserts bigint boolean declare enum implements infer interface is keyof namespace never number object private protected public readonly satisfies string symbol type unknown"
private let swiftKeywords = "actor any as associatedtype async await break case catch class continue convenience default defer deinit didSet do dynamic else enum extension fallthrough false fileprivate final for func get guard if import in indirect init inout internal is lazy let mutating nil nonisolated open operator optional override private protocol public repeat required rethrows return self set some static struct subscript super switch throw throws true try typealias unowned var weak where while willSet"
private let goKeywords = "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil iota append cap close copy delete len make new panic print println recover"
private let kotlinKeywords = "abstract annotation as break by catch class companion const constructor continue crossinline data do else enum external false final finally for fun get if import in infix init inline inner interface internal is lateinit noinline null object open operator out override package private protected public reified return sealed set super suspend this throw true try typealias val var vararg when where while"
private let sqlKeywords = "access add all alter and any as asc audit begin between body by case char check cluster column comment commit compress connect constant create cross current cursor date decimal declare default delete desc distinct drop else elsif end exception exclusive execute exists exit fetch file float for foreign from function grant group having identified if immediate in increment index initial inner insert integer intersect into is join key left level like limit lock long loop merge minus mode modify natural nocompress not nowait null number of offline on online open option or order outer over package partition pctfree pragma prior privileges procedure public raise range raw record references rename replace resource return returning revoke right role rollback row rowid rownum rows savepoint schema select sequence session set share size smallint start successful synonym sysdate table then to trigger truncate type uid union unique update user using validate values varchar varchar2 view when whenever where while with work fetch first next only nulls clob blob nclob nvarchar2 boolean bulk collect forall limit"
private let sqlFunctions = "abs avg ceil coalesce concat count cast decode dense_rank floor greatest instr lag last_day lead least length listagg lower lpad ltrim max min mod months_between nvl nvl2 power rank regexp_like regexp_replace regexp_substr replace round row_number rpad rtrim sign sqrt substr sum sys_guid systimestamp to_char to_date to_number to_timestamp trim trunc upper xmlagg json_value json_query json_table dbms_output put_line"
private let htmlKeywords = "a abbr address area article aside audio b base bdi bdo blockquote body br button canvas caption cite code col colgroup data datalist dd del details dfn dialog div dl dt em embed fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hr html i iframe img input ins kbd label legend li link main map mark meta meter nav noscript object ol optgroup option output p param picture pre progress q rp rt ruby s samp script section select slot small source span strong style sub summary sup svg table tbody td template textarea tfoot th thead time title tr track u ul var video wbr accept action alt async autocomplete autofocus charset checked class cols colspan content contenteditable crossorigin data defer dir disabled download draggable enctype for form height hidden href hreflang id lang list loop max maxlength media method min multiple name placeholder readonly rel required rows rowspan sandbox scope selected size span src srcset step style tabindex target title type value width onclick onload onchange onsubmit oninput onkeydown onkeyup"
