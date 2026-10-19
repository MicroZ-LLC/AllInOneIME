// The interface text and its language and the config's uiLanguage live in AllInOneIMEText, small enough for
// AllInOneIME Settings to link alone; whatever imports AllInOneIMECore gets them too.
@_exported import AllInOneIMEText

// The JavaScript engine's interface (ScriptEngine) lives in AllInOneIMEScriptEngine, so that an engine outside the core
// (AllInOneIMEQuickJS) can implement it; whatever imports AllInOneIMECore gets it too.
@_exported import AllInOneIMEScriptEngine
