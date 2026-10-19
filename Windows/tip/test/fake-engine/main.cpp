// A standalone fake engine: creates the §2.1 pipe (by default the real name, so the DLL in any app of this user
// connects) and replays a golden transcript, exactly, against the first DLL that connects: a real app's frames match
// only if it sends just what the golden lists. tiptest and wiretest use the same FakeEngine class in-process, on pipes
// of their own.
//
//   fake-engine <golden.jsonl> [pipeName]
//
// Prints the verdict and exits non-zero on a mismatch.

#include <windows.h>

#include <cstdio>
#include <string>

#include "test/common/FakeEngine.h"
#include "test/common/Transcript.h"

using namespace aio::test;

static std::wstring Widen(const std::string& s) {
    if (s.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
    std::wstring w(n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
    return w;
}

int main(int argc, char** argv) {
    setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc < 2) {
        printf("usage: fake-engine <golden.jsonl> [pipeName]\n");
        return 2;
    }
    Transcript t;
    std::string err;
    if (!Transcript::Load(argv[1], t, err)) {
        printf("load failed: %s\n", err.c_str());
        return 2;
    }
    std::wstring pipeName = argc > 2 ? Widen(argv[2]) : std::wstring();
    FakeEngine engine(std::move(t), pipeName);
    printf("fake-engine: listening (%s)\n", argv[1]);
    engine.Start();
    engine.Join();
    const auto& r = engine.Result();
    for (const auto& n : r.notes) printf("  . %s\n", n.c_str());
    printf("%s: %s\n", r.ok ? "PASS" : "FAIL", r.summary.c_str());
    return r.ok ? 0 : 1;
}
