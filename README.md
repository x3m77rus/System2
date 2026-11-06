# System2: Linux x86 / SourceMod 1.13

System2 provides HTTP/FTP requests, file operations, archive operations, and
system commands for SourceMod. This build targets a **32-bit Linux TF2 server
running SourceMod 1.13**. It uses Python 3, AMBuild 2.2, and C++17.

## Build from Windows

Install Docker Desktop with Linux containers. The workspace's `sdk/sourcemod`
must contain SourceMod **1.13** sources, including its SourcePawn and AMTL
submodules. From the workspace root:

```powershell
.\scripts\build-system2.ps1
.\scripts\build-system2.ps1 -Configuration Debug
```

This creates a dedicated `system2-ext-x86` image based on Ubuntu 22.04. The first
build downloads and compiles the dependencies; subsequent builds reuse Docker's
cache. The image is independent of the workspace's generic extension image.

Outputs are under `output/System2/release/` or `output/System2/debug/`:

- `system2.ext.so`: the 32-bit extension.
- `system2-linux-x86.tar.gz`: the deployable `addons/` tree.
- `package/addons/sourcemod/`: the same tree before compression.
- `build-manifest.json`: binary and CA hashes, SDK revision when available,
  dependency versions, dynamic dependencies, and the minimum required glibc.
- `dependencies.lock.json` and `licenses/`: dependency provenance and licenses.

Extract the tarball into the TF2 `tf/` directory. Deploy the full package so the
CA bundle and current archive executables are installed with the extension.
The tarball preserves executable permissions for the archive tools. The verified
build requires **glibc 2.34 or newer**; `minimum_glibc` is recorded in the manifest.
A 64-bit Linux host must have its 32-bit glibc runtime installed to run the TF2
server and extension.

## Dependencies

Reviewed against upstream releases on **2026-10-26**:

| Component | Version | Linkage / purpose |
| --- | --- | --- |
| [OpenSSL](https://openssl-library.org/source/) | 3.5.9 LTS | Static TLS backend; 3.5 is supported until April 2030 |
| [curl](https://curl.se/download.html) | 8.23.0 | Static HTTP/HTTPS/FTP/FTPS client |
| [zlib](https://zlib.net/) | 1.3.2 | Static gzip/deflate support |
| [libidn2](https://ftp.gnu.org/gnu/libidn/) | 2.3.8 | Static internationalized hostname support |
| [libunistring](https://ftp.gnu.org/gnu/libunistring/) | 1.5 | Static Unicode dependency of libidn2 |
| [7-Zip](https://www.7-zip.org/download.html) | 26.05 | Separate upstream x86/x64 executables replacing p7zip 16.02 |

All archives use HTTPS and pinned SHA-256 hashes in `dependencies.lock.json`.
The network libraries are compiled as 32-bit position-independent static
archives. libstdc++ and libgcc are linked statically too. The build rejects
unexpected shared dependencies and hides symbols from the static libraries to
avoid collisions with libraries used by other server extensions. The extension
still depends on the system's glibc and libm.

The CA bundle comes from the image's Ubuntu `ca-certificates` package. Rebuild
with `docker build --pull --no-cache -t system2-ext-x86 -f
extensions/System2/Dockerfile .` to refresh the base packages and trust store,
then run the PowerShell build script. Dependency releases stay pinned until
`dependencies.lock.json` is reviewed and updated. Static dependencies require
rebuilding and redeploying the extension to receive security updates.

HTTP/2, HTTP/3, LDAP, RTSP, SSH/SFTP, brotli, zstd, GSSAPI and libpsl are not
included. HTTP/HTTPS, FTP/FTPS, gzip and IDN are included. Windows builds and the
legacy Visual Studio project are outside this build's scope.

## Validation

Every build runs a 32-bit test process that opens the actual extension with
`dlopen` and checks its exported SourceMod API. A separate static client using
the same dependency archives checks HTTP redirects, POST, gzip, FTP, IDN,
trusted HTTPS, rejection of an untrusted certificate, and rejection of a wrong
TLS hostname. Both archive executables must pass an archive round trip.

These checks do not start TF2 or run SourcePawn callbacks in a live server.
Use `sm exts load system2` and `sm exts list` on the target server for that final
integration check. SourcePawn includes and test plugin sources are packaged;
plugin compilation is not required for the native extension build.

The C++ updates include the SourceMod 1.13 plugin-context API, libcurl's current
progress callback API and signatures, callback destruction, and CRC code that
compiles with C++17. The existing SourcePawn native names are retained.
