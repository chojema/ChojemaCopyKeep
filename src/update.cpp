#include "update.h"
#include <windows.h>
#include <winhttp.h>
#include <memory>
#include <stdexcept>

namespace copykeep {
Version check_update() {
    using Handle = std::unique_ptr<void,decltype(&WinHttpCloseHandle)>;
    Handle session(WinHttpOpen(L"ChojemaCopyKeep",
        WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0),WinHttpCloseHandle);
    if (!session || !WinHttpSetTimeouts(session.get(),5000,5000,5000,5000)) throw std::runtime_error("Update session failed");
    Handle connection(WinHttpConnect(session.get(),L"github.com",INTERNET_DEFAULT_HTTPS_PORT,0),WinHttpCloseHandle);
    if (!connection) throw std::runtime_error("Update connection failed");
    Handle request(WinHttpOpenRequest(connection.get(),L"HEAD",L"/chojema/ChojemaCopyKeep/releases/latest",
        nullptr,WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,WINHTTP_FLAG_SECURE),WinHttpCloseHandle);
    DWORD disabled=WINHTTP_DISABLE_REDIRECTS|WINHTTP_DISABLE_COOKIES|WINHTTP_DISABLE_AUTHENTICATION;
    if (!request || !WinHttpSetOption(request.get(),WINHTTP_OPTION_DISABLE_FEATURE,&disabled,sizeof(disabled)) ||
        !WinHttpSendRequest(request.get(),WINHTTP_NO_ADDITIONAL_HEADERS,0,WINHTTP_NO_REQUEST_DATA,0,0,0) ||
        !WinHttpReceiveResponse(request.get(),nullptr)) throw std::runtime_error("Update request failed");
    DWORD status=0, size=sizeof(status);
    if (!WinHttpQueryHeaders(request.get(),WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,
        WINHTTP_HEADER_NAME_BY_INDEX,&status,&size,WINHTTP_NO_HEADER_INDEX) || status!=302) throw std::runtime_error("Unexpected update response");
    wchar_t location[512]{}; size=sizeof(location);
    if (!WinHttpQueryHeaders(request.get(),WINHTTP_QUERY_LOCATION,WINHTTP_HEADER_NAME_BY_INDEX,
        location,&size,WINHTTP_NO_HEADER_INDEX)) throw std::runtime_error("Missing update location");
    auto version=release_version(location);
    if (!version) throw std::runtime_error("Unsupported release version");
    return *version;
}
}
