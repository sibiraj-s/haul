import AppKit

// `haul`, the command-line tool in Haul.app/Contents/Helpers. It opens Haul's Add panel with
// the links filled in, like a haul://add link, so nothing downloads until it's confirmed there.

let usage = """
    Usage: haul add <link>...
           haul add < links.txt

    Opens Haul's Add panel with the links filled in. With no links given, they're
    read from standard input, separated by spaces or new lines.

    Options:
      -h, --help     Show this help
      -v, --version  Show Haul's version

    """

func fail(_ message: String, status: Int32 = EX_USAGE) -> Never {
    FileHandle.standardError.write(Data("haul: \(message)\n".utf8))
    exit(status)
}

/// Haul.app, found from where this tool really is: it usually runs through a symlink.
let app = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

let arguments = Array(CommandLine.arguments.dropFirst())
if NativeHost.isBrowser(arguments) {
    await NativeHost.run(app: app)
    exit(EX_OK)
}
switch arguments.first {
case "-h", "--help", "help":
    print(usage, terminator: "")
case "-v", "--version":
    print(Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
case "add":
    var words = Array(arguments.dropFirst())
    if words.isEmpty, isatty(STDIN_FILENO) == 0 {
        let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        words = input.split(whereSeparator: \.isWhitespace).map(String.init)
    }
    guard !words.isEmpty else { fail("no links given. Run haul --help for usage.") }
    let links = words.map { word in
        guard let url = URL(string: word), OpenInHaul.isDownloadLink(url), url.host() != nil else {
            fail("not an http or https link: \(word)", status: EX_DATAERR)
        }
        return url
    }
    await OpenInHaul.open(links, in: app)
case nil:
    FileHandle.standardError.write(Data(usage.utf8))
    exit(EX_USAGE)
case let command?:
    fail("unknown command \(command). Run haul --help for usage.")
}
