// Off Apple platforms URLSession and XMLParser are in modules of their own: every test file gets them here, as Apple's
// Foundation gives them.
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif
#if canImport(FoundationXML)
@_exported import FoundationXML
#endif
