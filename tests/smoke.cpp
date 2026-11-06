#include <IExtensionSys.h>
#include <curl/curl.h>
#include <openssl/crypto.h>
#include <zlib.h>
#include <idn2.h>
#include "RequestThread.h"
#include "LegacyDownloadThread.h"
#include "3rdparty/crc/crc.h"
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <type_traits>

static_assert(sizeof(void*) == 4, "Smoke test must run as a 32-bit process");
static_assert(std::is_same<decltype(&RequestThread::ProgressUpdated), curl_xferinfo_callback>::value,
              "Request progress callback must match libcurl's ABI");
static_assert(std::is_same<decltype(&LegacyDownloadThread::ProgressUpdated), curl_xferinfo_callback>::value,
              "Legacy progress callback must match libcurl's ABI");

static void require(bool value, const char* message) {
    if (!value) { std::fprintf(stderr, "%s\n", message); std::exit(1); }
}
static size_t receive(char* ptr, size_t size, size_t count, void* user) {
    static_cast<std::string*>(user)->append(ptr, size * count);
    return size * count;
}
static CURLcode request(const std::string& url, std::string& result, const char* ca = nullptr,
                        const char* post = nullptr) {
    CURL* curl = curl_easy_init();
    require(curl != nullptr, "curl_easy_init failed");
    result.clear();
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_PROXY, "");
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, receive);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &result);
    if (ca) curl_easy_setopt(curl, CURLOPT_CAINFO, ca);
    if (post) curl_easy_setopt(curl, CURLOPT_POSTFIELDS, post);
    CURLcode code = curl_easy_perform(curl);
    curl_easy_cleanup(curl);
    return code;
}
int main(int argc, char** argv) {
    require(argc == 7, "Expected extension, HTTP, HTTPS, FTP, CA, and wrong-host URLs");
    char crc_input[] = "123456789";
    require(crc32buf(crc_input, 9) == 0xcbf43926U, "CRC32 reference vector failed");
    void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { std::fprintf(stderr, "%s\n", dlerror()); return 1; }
    auto entry = reinterpret_cast<SourceMod::IExtensionInterface*(*)()>(dlsym(library, "GetSMExtAPI"));
    require(entry != nullptr, "GetSMExtAPI is not exported");
    auto api = entry();
    require(api && api->GetExtensionVersion() == SMINTERFACE_EXTENSIONAPI_VERSION,
            "SourceMod extension API version mismatch");
    require(std::strcmp(api->GetExtensionName(), "System2") == 0, "Unexpected extension name");
    std::printf("Loaded %s %s; SourceMod API %u\n", api->GetExtensionName(),
                api->GetExtensionVerString(), api->GetExtensionVersion());

    require(curl_global_init(CURL_GLOBAL_ALL) == CURLE_OK, "curl_global_init failed");
    const auto info = curl_version_info(CURLVERSION_NOW);
    require(std::strcmp(info->version, LIBCURL_VERSION) == 0, "curl header/runtime mismatch");
    require(std::strcmp(info->libz_version, ZLIB_VERSION) == 0, "zlib header/runtime mismatch");
    require((info->features & (CURL_VERSION_SSL | CURL_VERSION_LIBZ | CURL_VERSION_IDN)) ==
            (CURL_VERSION_SSL | CURL_VERSION_LIBZ | CURL_VERSION_IDN), "Missing TLS/zlib/IDN support");
    std::printf("%s\n%s\nzlib %s; libidn2 %s\n", curl_version(), OpenSSL_version(OPENSSL_VERSION),
                zlibVersion(), idn2_check_version(nullptr));
    uint8_t* ascii = nullptr;
    require(idn2_lookup_u8(reinterpret_cast<const uint8_t*>("b\xc3\xbc" "cher.example"),
                           &ascii, 0) == IDN2_OK, "IDN conversion failed");
    require(std::strcmp(reinterpret_cast<char*>(ascii), "xn--bcher-kva.example") == 0,
            "Incorrect IDN conversion");
    idn2_free(ascii);

    std::string result;
    std::string body;
    for (int i = 0; i < 64; ++i) body += "System2 smoke test\n";
    require(request(std::string(argv[2]) + "/redirect", result) == CURLE_OK && result == body,
            "HTTP redirect/gzip transfer failed");
    require(request(std::string(argv[2]) + "/post", result, nullptr, "upload=system2") == CURLE_OK &&
            result == "upload=system2", "HTTP POST failed");
    require(request(argv[3], result) == CURLE_PEER_FAILED_VERIFICATION,
            "Untrusted TLS certificate was not rejected");
    require(request(argv[3], result, argv[5]) == CURLE_OK && result == body,
            "Trusted HTTPS/gzip transfer failed");
    require(request(argv[6], result, argv[5]) == CURLE_PEER_FAILED_VERIFICATION,
            "TLS hostname mismatch was not rejected");
    require(request(argv[4], result) == CURLE_OK && result == "System2 FTP smoke test\n",
            "FTP download failed");
    curl_global_cleanup();
    dlclose(library);
    std::puts("32-bit loader, HTTP, POST, gzip, TLS verification, FTP and IDN checks passed.");
}
