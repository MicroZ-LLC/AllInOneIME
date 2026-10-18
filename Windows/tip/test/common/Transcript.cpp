#include <windows.h>

#include "Transcript.h"

#include <fstream>
#include <sstream>

namespace aio::test {

using nlohmann::json;

namespace {

std::string Trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    size_t b = s.find_last_not_of(" \t\r\n");
    return a == std::string::npos ? std::string() : s.substr(a, b - a + 1);
}

// vk for a letter/char key the directive names, so `#! type` can say `char=h` instead of a vk number.
WORD VkForChar(char c) {
    if (c >= 'a' && c <= 'z') return static_cast<WORD>('A' + (c - 'a'));
    if (c >= 'A' && c <= 'Z') return static_cast<WORD>(c);
    if (c >= '0' && c <= '9') return static_cast<WORD>(c);
    return 0;
}

// A `#! type` line: `down|up vk=50 scan=3 [char=@] [shift] [lshift] [ctrl] ...`
TypeKey ParseType(const std::string& arg) {
    TypeKey k;
    std::istringstream in(arg);
    std::string tok;
    bool first = true;
    while (in >> tok) {
        if (first) {
            k.down = (tok != "up");
            first = false;
            continue;
        }
        auto eq = tok.find('=');
        if (eq != std::string::npos) {
            std::string name = tok.substr(0, eq), value = tok.substr(eq + 1);
            if (name == "vk") k.vk = static_cast<WORD>(strtol(value.c_str(), nullptr, 0));
            else if (name == "scan") k.scan = static_cast<WORD>(strtol(value.c_str(), nullptr, 0));
            else if (name == "char" && !value.empty()) { if (!k.vk) k.vk = VkForChar(value[0]); }
        } else {
            k.setsState = true;
            if (tok == "shift") { k.shift = k.lshift = true; }
            else if (tok == "lshift") { k.shift = k.lshift = true; }
            else if (tok == "rshift") { k.shift = k.rshift = true; }
            else if (tok == "ctrl") { k.ctrl = k.lctrl = true; }
            else if (tok == "alt") { k.alt = k.lalt = true; }
            else if (tok == "extended") k.extended = true;
        }
    }
    return k;
}

// Derives the key to synthesize from a `>` keyDown/keyUp frame (its vk/scan/modifiers).
TypeKey KeyFromFrame(const json& body, bool down) {
    TypeKey k;
    k.down = down;
    const auto& key = body.at("key");
    k.vk = static_cast<WORD>(key.value("vk", 0));
    k.scan = static_cast<WORD>(key.value("scan", 0));
    k.extended = key.value("extended", false);
    if (key.contains("modifiers")) {
        for (const auto& m : key.at("modifiers")) {
            const std::string name = m.get<std::string>();
            k.setsState = true;
            if (name == "shift") k.shift = true;
            else if (name == "leftShift") { k.shift = k.lshift = true; }
            else if (name == "rightShift") { k.shift = k.rshift = true; }
            else if (name == "control") k.ctrl = true;
            else if (name == "leftControl") { k.ctrl = k.lctrl = true; }
            else if (name == "rightControl") { k.ctrl = k.rctrl = true; }
            else if (name == "option") k.alt = true;
            else if (name == "leftOption") { k.alt = k.lalt = true; }
            else if (name == "rightOption") { k.alt = k.ralt = true; }
        }
    }
    return k;
}

std::wstring Widen(const std::string& utf8) {
    if (utf8.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), (int)utf8.size(), nullptr, 0);
    std::wstring out(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8.data(), (int)utf8.size(), out.data(), n);
    return out;
}

bool IsAny(const json& j) { return j.is_string() && j.get<std::string>() == "$any"; }

} // namespace

bool Matches(const json& expected, const json& actual) {
    if (IsAny(expected)) return true;
    if (expected.type() != actual.type()) {
        // Accept unsigned/signed integer sameness.
        if (expected.is_number_integer() && actual.is_number_integer()) return expected.get<long long>() == actual.get<long long>();
        return false;
    }
    if (expected.is_object()) {
        // Every expected key must match; actual must carry no extra keys (so stray frames are caught).
        for (auto it = expected.begin(); it != expected.end(); ++it) {
            auto a = actual.find(it.key());
            if (a == actual.end()) return false;
            if (!Matches(it.value(), *a)) return false;
        }
        for (auto it = actual.begin(); it != actual.end(); ++it) {
            if (!expected.contains(it.key())) return false;
        }
        return true;
    }
    if (expected.is_array()) {
        if (expected.size() != actual.size()) return false;
        for (size_t i = 0; i < expected.size(); ++i) {
            if (!Matches(expected[i], actual[i])) return false;
        }
        return true;
    }
    return expected == actual;
}

json NormalizeExpected(const json& expected) {
    json e = expected;
    if (e.is_object()) {
        const std::string type = e.value("type", "");
        if (type == "keyDown" || type == "keyUp") e["t"] = "$any"; // GetTickCount64, §5.1 — host can't reproduce it
        else if (e.contains("t")) e["t"] = "$any";
        if (type == "hello") { // the DLL's real process/thread ids, not the spec's illustrative 4242/4250
            e["pid"] = "$any";
            e["tid"] = "$any";
        }
        if (e.contains("field") && e["field"].is_object()) {
            for (const char* f : {"app", "process", "layout"}) {
                if (e["field"].contains(f)) e["field"][f] = "$any";
            }
        }
    }
    return e;
}

std::string Brief(const json& body) {
    return body.dump();
}

bool Transcript::Load(const std::string& path, Transcript& out, std::string& error) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        error = "can't open " + path;
        return false;
    }
    out = Transcript{};
    std::string raw;
    int lineNo = 0;
    while (std::getline(in, raw)) {
        ++lineNo;
        std::string line = Trim(raw);
        if (line.empty()) continue;
        Line entry;
        if (line.rfind("#!", 0) == 0) {
            entry.kind = Line::Kind::directive;
            std::string rest = Trim(line.substr(2));
            auto sp = rest.find_first_of(" \t");
            entry.directive = sp == std::string::npos ? rest : rest.substr(0, sp);
            entry.arg = sp == std::string::npos ? "" : Trim(rest.substr(sp + 1));
            if (entry.directive == "no-engine") out.noEngine = true;
            else if (entry.directive == "secure") out.secure = true;
            else if (entry.directive == "expect-silence") out.expectSilence = true;
            else if (entry.directive == "double-test") out.doubleTest = true;
            else if (entry.directive == "expect-document") {
                out.hasExpectDocument = true;
                std::string a = entry.arg;
                if (a.size() >= 2 && a.front() == '"' && a.back() == '"') a = a.substr(1, a.size() - 2);
                out.expectDocument = Widen(a);
            } else if (entry.directive == "type") {
                out.steps.push_back({Step::Kind::key, ParseType(entry.arg), 0});
            } else if (entry.directive == "terminate") {
                out.steps.push_back({Step::Kind::terminate, {}, 0});
            } else if (entry.directive == "wait") {
                out.steps.push_back({Step::Kind::wait, {}, static_cast<DWORD>(strtoul(entry.arg.c_str(), nullptr, 10))});
            }
            out.lines.push_back(std::move(entry));
            continue;
        }
        if (line[0] == '#') {
            entry.kind = Line::Kind::comment;
            out.lines.push_back(std::move(entry));
            continue;
        }
        if (line[0] == '>' || line[0] == '<') {
            const bool fromDll = line[0] == '>';
            entry.kind = fromDll ? Line::Kind::fromDll : Line::Kind::fromEngine;
            std::string jsonText = Trim(line.substr(1));
            entry.body = json::parse(jsonText, nullptr, false);
            if (entry.body.is_discarded() || !entry.body.is_object()) {
                error = path + ":" + std::to_string(lineNo) + ": bad JSON";
                return false;
            }
            const std::string type = entry.body.value("type", "");
            if (fromDll && (type == "keyDown" || type == "keyUp") && entry.body.contains("key")) {
                out.steps.push_back({Step::Kind::key, KeyFromFrame(entry.body, type == "keyDown"), 0});
            }
            out.lines.push_back(std::move(entry));
            continue;
        }
        error = path + ":" + std::to_string(lineNo) + ": unknown line";
        return false;
    }

    return true;
}

} // namespace aio::test
