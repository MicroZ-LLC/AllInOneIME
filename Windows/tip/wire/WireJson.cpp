// The JSON of the wire structs (Wire.h), written by hand over nlohmann/json.
//
// Reading uses `json::parse(…, callback, false)` and checked accessors only, so bad input never throws; the whole of
// each entry point is inside a try block all the same (allocation can throw), and nothing escapes.

#include "wire/Wire.h"

#include <windows.h>

#include <algorithm>

#include <nlohmann/json.hpp>

namespace aio::wire {

using nlohmann::json;

namespace {

constexpr int kMaxDepth = 16;

std::string Dump(const json& j) {
    return j.dump(-1, ' ', false, json::error_handler_t::replace);
}

json Envelope(uint32_t id, const char* type) {
    json j = json::object();
    j["v"] = kVersion;
    j["id"] = id;
    j["type"] = type;
    return j;
}

void PutText(json& j, const char* name, const Text& text) {
    if (!text.empty()) j[name] = ToUtf8(text);
}

void PutString(json& j, const char* name, const std::string& text) {
    if (!text.empty()) j[name] = text;
}

void PutBool(json& j, const char* name, bool value) {
    if (value) j[name] = true;
}

json FieldJson(const FieldInfo& field) {
    json f = json::object();
    PutString(f, "app", field.app);
    PutString(f, "process", field.process);
    PutBool(f, "secure", field.secure);
    PutBool(f, "readOnly", field.readOnly);
    if (!field.scopes.empty()) f["scopes"] = field.scopes;
    PutString(f, "layout", field.layout);
    return f;
}

json ContextJson(const FieldContext& ctx) {
    json c = json::object();
    if (ctx.sel) c["sel"] = json::array({ctx.sel->first, ctx.sel->second});
    PutText(c, "before", ctx.before);
    PutText(c, "selText", ctx.selText);
    PutBool(c, "selTruncated", ctx.selTruncated);
    if (ctx.comp) c["comp"] = *ctx.comp;
    return c;
}

json ModifiersJson(uint16_t modifiers) {
    json names = json::array();
    for (size_t bit = 0; bit < std::size(kModifierNames); ++bit) {
        if (modifiers & (1u << bit)) names.push_back(kModifierNames[bit]);
    }
    return names;
}

// ---- checked readers ----

bool ReadU32(const json& j, const char* name, uint32_t& out, bool& bad) {
    auto it = j.find(name);
    if (it == j.end() || it->is_null()) return false;
    if (it->is_number_unsigned()) {
        auto v = it->get<uint64_t>();
        if (v <= UINT32_MAX) {
            out = static_cast<uint32_t>(v);
            return true;
        }
    } else if (it->is_number_integer()) {
        auto v = it->get<int64_t>();
        if (v >= 0 && v <= INT64_C(0xFFFFFFFF)) {
            out = static_cast<uint32_t>(v);
            return true;
        }
    }
    bad = true;
    return false;
}

bool ReadI64(const json& j, const char* name, int64_t& out, bool& bad) {
    auto it = j.find(name);
    if (it == j.end() || it->is_null()) return false;
    if (it->is_number_integer()) { // signed or unsigned
        if (it->is_number_unsigned() && it->get<uint64_t>() > static_cast<uint64_t>(INT64_MAX)) {
            bad = true;
            return false;
        }
        out = it->get<int64_t>();
        return true;
    }
    bad = true;
    return false;
}

bool ReadBool(const json& j, const char* name, bool& out, bool& bad) {
    auto it = j.find(name);
    if (it == j.end() || it->is_null()) return false;
    if (it->is_boolean()) {
        out = it->get<bool>();
        return true;
    }
    bad = true;
    return false;
}

bool ReadString(const json& j, const char* name, std::string& out, bool& bad) {
    auto it = j.find(name);
    if (it == j.end() || it->is_null()) return false;
    if (it->is_string()) {
        out = it->get_ref<const std::string&>();
        return true;
    }
    bad = true;
    return false;
}

bool ReadText(const json& j, const char* name, Text& out, bool& bad) {
    std::string utf8;
    if (!ReadString(j, name, utf8, bad)) return false;
    if (!FromUtf8(utf8, out)) {
        bad = true;
        return false;
    }
    return true;
}

bool ReadStringArray(const json& j, const char* name, std::vector<std::string>& out, bool& bad) {
    auto it = j.find(name);
    if (it == j.end() || it->is_null()) return false;
    if (!it->is_array()) {
        bad = true;
        return false;
    }
    out.clear();
    for (const auto& e : *it) {
        if (e.is_string()) out.push_back(e.get<std::string>()); // others are left out
    }
    return true;
}

bool ParseStyle(const std::string& name, Style& out) {
    if (name == "raw") out = Style::raw;
    else if (name == "draft") out = Style::draft;
    else if (name == "converted") out = Style::converted;
    else if (name == "target") out = Style::target;
    else return false;
    return true;
}

// The ops of an `outputs` array; unknown ops are skipped (§9).
bool ReadOutputs(const json& j, std::vector<Output>& out, bool& bad) {
    auto it = j.find("outputs");
    if (it == j.end() || it->is_null()) return true;
    if (!it->is_array()) {
        bad = true;
        return false;
    }
    for (const auto& o : *it) {
        if (!o.is_object()) {
            bad = true;
            return false;
        }
        std::string op;
        if (!ReadString(o, "op", op, bad)) {
            bad = true;
            return false;
        }
        if (op == "commit") {
            CommitOutput c;
            ReadText(o, "text", c.text, bad);
            ReadI64(o, "deleteBefore", c.deleteBefore, bad);
            ReadI64(o, "deleteAfter", c.deleteAfter, bad);
            ReadBool(o, "afterKey", c.afterKey, bad);
            if (c.deleteBefore < 0 || c.deleteAfter < 0) bad = true;
            out.emplace_back(std::move(c));
        } else if (op == "composition") {
            CompositionOutput c;
            ReadText(o, "text", c.text, bad);
            ReadI64(o, "caret", c.caret, bad);
            auto segs = o.find("segments");
            if (segs != o.end() && !segs->is_null()) {
                if (!segs->is_array()) {
                    bad = true;
                } else {
                    for (const auto& s : *segs) {
                        if (!s.is_object()) {
                            bad = true;
                            break;
                        }
                        Segment seg;
                        ReadI64(s, "from", seg.from, bad);
                        ReadI64(s, "to", seg.to, bad);
                        std::string style;
                        if (ReadString(s, "style", style, bad) && !ParseStyle(style, seg.style)) {
                            seg.style = Style::raw; // unknown styles are raw (§6)
                        }
                        c.segments.push_back(seg);
                    }
                }
            }
            out.emplace_back(std::move(c));
        } else if (op == "panel") {
            PanelOutput p;
            ReadBool(o, "shown", p.shown, bad);
            out.emplace_back(p);
        } else if (op == "allowForeground") {
            out.emplace_back(AllowForegroundOutput{});
        }
        if (bad) return false;
    }
    return true;
}

} // namespace

// ---- encoders ----

std::string Encode(const Hello& m) noexcept {
    try {
        json j = Envelope(m.id, "hello");
        j["versions"] = m.versions;
        PutString(j, "client", m.client);
        j["platform"] = "win";
        PutString(j, "arch", m.arch);
        j["pid"] = m.pid;
        j["tid"] = m.tid;
        if (!m.capabilities.empty()) j["capabilities"] = m.capabilities;
        return Dump(j);
    } catch (...) {
        return {};
    }
}

std::string Encode(const Open& m) noexcept {
    try {
        json j = Envelope(m.id, "open");
        j["sid"] = m.sid;
        j["field"] = FieldJson(m.field);
        return Dump(j);
    } catch (...) {
        return {};
    }
}

std::string Encode(const Focus& m) noexcept {
    try {
        json j = Envelope(m.id, "focus");
        j["sid"] = m.sid;
        j["focus"] = m.focus;
        if (m.field) j["field"] = FieldJson(*m.field);
        return Dump(j);
    } catch (...) {
        return {};
    }
}

std::string Encode(const Blur& m) noexcept {
    try {
        json j = Envelope(m.id, "blur");
        j["sid"] = m.sid;
        return Dump(j);
    } catch (...) {
        return {};
    }
}

std::string Encode(const Close& m) noexcept {
    try {
        json j = Envelope(m.id, "close");
        j["sid"] = m.sid;
        return Dump(j);
    } catch (...) {
        return {};
    }
}

std::string Encode(const KeyEvent& m) noexcept {
    try {
        json j = Envelope(m.id, m.down ? "keyDown" : "keyUp");
        j["sid"] = m.sid;
        if (m.t) j["t"] = m.t;
        json k = json::object();
        k["vk"] = m.key.vk;
        if (m.key.scan) k["scan"] = m.key.scan;
        PutBool(k, "extended", m.key.extended);
        PutText(k, "text", m.key.text);
        PutText(k, "textIgnoringModifiers", m.key.textIgnoringModifiers);
        PutBool(k, "isDeadKey", m.key.isDeadKey);
        PutBool(k, "isRepeat", m.key.isRepeat);
        if (m.key.modifiers) k["modifiers"] = ModifiersJson(m.key.modifiers);
        j["key"] = std::move(k);
        j["ctx"] = ContextJson(m.ctx);
        return Dump(j);
    } catch (...) {
        return {};
    }
}

std::string Encode(const EndComposition& m) noexcept {
    try {
        json j = Envelope(m.id, "endComposition");
        j["sid"] = m.sid;
        PutString(j, "reason", m.reason);
        return Dump(j);
    } catch (...) {
        return {};
    }
}

std::string Encode(const Ping& m) noexcept {
    try {
        return Dump(Envelope(m.id, "ping"));
    } catch (...) {
        return {};
    }
}

std::string Encode(const Caret& m) noexcept {
    try {
        json j = Envelope(m.id, "caret");
        j["sid"] = m.sid;
        j["rect"] = json::array({m.rect[0], m.rect[1], m.rect[2], m.rect[3]});
        if (!m.exact) j["exact"] = false; // the default is true: written only when false
        j["hwnd"] = m.hwnd;
        return Dump(j);
    } catch (...) {
        return {};
    }
}

std::string Encode(const Applied& m) noexcept {
    try {
        json j = Envelope(m.id, "applied");
        j["re"] = m.re;
        PutBool(j, "ok", m.ok);
        PutString(j, "reason", m.reason);
        if (m.ctx) j["ctx"] = ContextJson(*m.ctx);
        return Dump(j);
    } catch (...) {
        return {};
    }
}

// ---- decoder ----

DecodeError Decode(std::string_view body, EngineMessage& out) noexcept {
    try {
        bool tooDeep = false;
        json::parser_callback_t depthCheck = [&tooDeep](int depth, json::parse_event_t, json&) {
            if (depth > kMaxDepth) tooDeep = true;
            return !tooDeep;
        };
        json j = json::parse(body.begin(), body.end(), depthCheck, false);
        if (tooDeep || j.is_discarded() || !j.is_object()) return DecodeError::badFrame;

        bool bad = false;
        out = EngineMessage{};
        int64_t v = kVersion;
        ReadI64(j, "v", v, bad);
        if (bad || v != kVersion) return DecodeError::badMessage;
        if (!ReadString(j, "type", out.typeName, bad)) return DecodeError::badMessage;
        ReadU32(j, "id", out.id, bad);
        uint32_t re = 0;
        if (ReadU32(j, "re", re, bad)) out.re = re;
        if (bad) return DecodeError::badMessage;

        const std::string& type = out.typeName;
        if (type == "welcome") {
            out.type = EngineType::welcome;
            int64_t version = 0;
            if (!ReadI64(j, "version", version, bad)) bad = true;
            out.welcome.version = static_cast<int>(version);
            ReadString(j, "engine", out.welcome.engine, bad);
            ReadU32(j, "enginePid", out.welcome.enginePid, bad);
            ReadStringArray(j, "capabilities", out.welcome.capabilities, bad);
            auto limits = j.find("limits");
            if (limits != j.end() && limits->is_object()) {
                int64_t n = 0;
                if (ReadI64(*limits, "contextBefore", n, bad)) {
                    out.welcome.limits.contextBefore = static_cast<int>(std::clamp<int64_t>(n, 0, 256));
                }
                if (ReadI64(*limits, "selection", n, bad)) {
                    out.welcome.limits.selection = static_cast<int>(std::clamp<int64_t>(n, 0, 1 << 20));
                }
            }
        } else if (type == "result") {
            out.type = EngineType::result;
            if (!out.re) bad = true;
            ReadBool(j, "handled", out.result.handled, bad);
            ReadOutputs(j, out.result.outputs, bad);
        } else if (type == "pong") {
            out.type = EngineType::pong;
        } else if (type == "error") {
            out.type = EngineType::error;
            ReadString(j, "code", out.code, bad);
        } else if (type == "bye") {
            out.type = EngineType::bye;
            ReadString(j, "reason", out.reason, bad);
            uint32_t retry = 0;
            if (ReadU32(j, "retryMs", retry, bad)) out.retryMs = retry;
        } else if (type == "apply") {
            out.type = EngineType::apply;
            if (!ReadU32(j, "sid", out.sid, bad)) bad = true;
            ReadU32(j, "focus", out.focus, bad);
            ReadOutputs(j, out.result.outputs, bad);
        } else {
            out.type = EngineType::unknown;
        }
        return bad ? DecodeError::badMessage : DecodeError::none;
    } catch (...) {
        return DecodeError::badFrame;
    }
}

// ---- framing ----

std::string Frame(std::string_view body) {
    std::string frame;
    frame.reserve(body.size() + 4);
    const auto n = static_cast<uint32_t>(body.size());
    frame.push_back(static_cast<char>(n & 0xFF));
    frame.push_back(static_cast<char>((n >> 8) & 0xFF));
    frame.push_back(static_cast<char>((n >> 16) & 0xFF));
    frame.push_back(static_cast<char>((n >> 24) & 0xFF));
    frame.append(body);
    return frame;
}

bool Unframe(std::string_view message, std::string_view& body) noexcept {
    if (message.size() < 4) return false;
    const auto* p = reinterpret_cast<const unsigned char*>(message.data());
    const uint32_t n = p[0] | (p[1] << 8) | (p[2] << 16) | (static_cast<uint32_t>(p[3]) << 24);
    if (n != message.size() - 4) return false;
    body = message.substr(4);
    return true;
}

// ---- text ----

std::string ToUtf8(std::wstring_view text) noexcept {
    try {
        if (text.empty()) return {};
        const int n = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0,
                                          nullptr, nullptr);
        if (n <= 0) return {};
        std::string out(static_cast<size_t>(n), '\0');
        WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), n, nullptr, nullptr);
        return out;
    } catch (...) {
        return {};
    }
}

bool FromUtf8(std::string_view utf8, std::wstring& out) noexcept {
    try {
        out.clear();
        if (utf8.empty()) return true;
        const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), static_cast<int>(utf8.size()),
                                          nullptr, 0);
        if (n <= 0) return false;
        out.resize(static_cast<size_t>(n));
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), static_cast<int>(utf8.size()), out.data(), n);
        return true;
    } catch (...) {
        return false;
    }
}

const char* StyleName(Style style) noexcept {
    switch (style) {
    case Style::raw: return "raw";
    case Style::draft: return "draft";
    case Style::converted: return "converted";
    case Style::target: return "target";
    }
    return "raw";
}

} // namespace aio::wire
