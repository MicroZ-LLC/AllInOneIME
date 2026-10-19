// Our composition in one ITfContext (§6): starting it, setting its text and segment styles, committing, and ending it
// while keeping its text in the document.
//
// Every method runs inside an edit session with the write cookie it is given. A Composition owns no edit session of
// its own; the Session arranges those. It holds a reference to its ITfContext and, while composing, to the
// ITfComposition TSF gave it.

#pragma once

#include <windows.h>
#include <msctf.h>

#include <vector>

#include "DisplayAttributes.h"
#include "wire/Wire.h"

namespace aio {

class Composition {
public:
    Composition(ITfContext* context, TfClientId clientId, const DisplayAttributeAtoms* atoms,
                ITfCompositionSink* sink) noexcept;
    ~Composition();
    Composition(const Composition&) = delete;
    Composition& operator=(const Composition&) = delete;

    bool Active() const noexcept { return composition_ != nullptr; }

    // §6 `composition`: start if needed, set the text, mark the segments, put the caret at start + `caret`. Empty text
    // removes the text and ends the composition.
    HRESULT SetComposition(TfEditCookie ec, const wire::CompositionOutput& output) noexcept;

    // §6 `commit`: R is the composition range if composing (or the range a terminated composition covered, §5.5), else
    // the selection; extend R by deleteBefore/deleteAfter (clamped), replace it with `text`, end the composition, and
    // put the caret after `text`.
    HRESULT Commit(TfEditCookie ec, const wire::CommitOutput& output) noexcept;

    // End the composition, keeping its text (§2.5): the draft as the user typed it (`typed`), if the engine showed it
    // otherwise and the document still holds what was shown; else the text as it is. Clears the display attributes and
    // puts the caret after the text. No-op if not composing.
    HRESULT EndKeepingText(TfEditCookie ec) noexcept;

    // The length of the composition as the document has it now (§5.1 `comp`), or nullopt if not composing.
    bool CompositionLength(TfEditCookie ec, LONG& length) const noexcept;

    // The range the composition covers (for the caret report), AddRef'd; null if not composing.
    HRESULT GetRange(ITfRange** range) const noexcept;

    ITfComposition* Raw() const noexcept { return composition_; }

    // TSF ended it for us (OnCompositionTerminated): drop our reference, but keep the range it covered, so the result of
    // `endComposition {terminated}` can replace it (§5.5). ForgetRange drops that once the result is applied.
    void Terminated() noexcept;
    void ForgetRange() noexcept;

private:
    HRESULT Start(TfEditCookie ec) noexcept;
    HRESULT ClearDisplayAttributes(TfEditCookie ec) noexcept;
    HRESULT MarkSegments(TfEditCookie ec, ITfRange* fullRange, const wire::CompositionOutput& output) noexcept;
    HRESULT SetSelection(TfEditCookie ec, ITfRange* start, LONG offset) noexcept;
    static bool ReadText(TfEditCookie ec, ITfRange* range, wire::Text& out) noexcept;

    ITfContext* context_ = nullptr;
    TfClientId clientId_ = TF_CLIENTID_NULL;
    const DisplayAttributeAtoms* atoms_ = nullptr;
    ITfCompositionSink* sink_ = nullptr;
    ITfComposition* composition_ = nullptr;
    ITfRange* terminatedRange_ = nullptr;
    wire::Text shown_; // the text we last set
    wire::Text typed_; // what was typed, when that isn't `shown_`
};

} // namespace aio
