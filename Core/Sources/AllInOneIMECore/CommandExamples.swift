import Foundation

/// Commands Settings offers to start a command of the user's own from (Add Command… → Start from an Example), that the
/// core knows of. Once added, each is the user's own like any other: edited, synced, deleted as they are.
public enum CommandExamples {
    /// `@py 2**100`: a line of Python run with the user's `python3`, REPL style (`pythonREPL`). Not offered without it
    /// (`Command.program`). Its summary is in the interface language of the moment, hence computed.
    public static var python: CustomCommand {
        CustomCommand(name: "py", type: .run, summary: tr("运行 Python，结果可以直接上屏", "Run Python; insert the result"),
                      argv: ["python3", "-X", "utf8", "-c", pythonREPL], stdin: CustomCommand.placeholder, ascii: true,
                      color: "blue")
    }

    /// Runs the code on standard input like IPython does a cell: `ast` splits off a last expression, the rest is executed,
    /// then the expression's value is printed (a str as it is, anything else with repr; None not at all). An error is
    /// Python's own (the runner shows its last line), and `sys.exit` works as usual. The code runs in a namespace of its own
    /// (`__name__` is "__main__"). The working directory (the home folder) is left out of `sys.path` while this imports
    /// `ast`, so an `ast.py` there can't stand in for it; the code itself can import from it, as with `python3 -c`. One
    /// line: the editor's Command field is one line.
    public static let pythonREPL = "import sys;c=sys.path.pop(0) if sys.path[:1]==[''] else None;import ast;"
        + "c is None or sys.path.insert(0,c);t=ast.parse(sys.stdin.read(),'<input>');"
        + "e=t.body.pop() if t.body and isinstance(t.body[-1],ast.Expr) else None;g={'__name__':'__main__'};"
        + "exec(compile(t,'<input>','exec'),g);"
        + "v=None if e is None else eval(compile(ast.Expression(e.value),'<input>','eval'),g);"
        + "v is None or print(v if isinstance(v,str) else repr(v))"
}
