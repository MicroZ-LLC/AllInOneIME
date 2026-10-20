// GUIDs the Windows SDK import libraries don't provide a definition for. INITGUID turns the DEFINE_GUID below into a
// definition (with external linkage) rather than a declaration.
//
// Only GUID_PROP_INPUTSCOPE is here: InputScope.h DEFINE_GUIDs it but no import library carries it. Its IIDs
// (IID_ITfInputScope …) are in uuid.lib, so this file does NOT include InputScope.h under INITGUID, which would
// redefine them and clash at link time.

#include <windows.h>

#include <initguid.h>

DEFINE_GUID(GUID_PROP_INPUTSCOPE, 0x1713dd5a, 0x68e7, 0x4a5b, 0x9a, 0xf6, 0x59, 0x2a, 0x59, 0x5c, 0x77, 0x8d);
