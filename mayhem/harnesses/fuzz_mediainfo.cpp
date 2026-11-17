// libFuzzer harness over MediaInfoLib's public API, the way an embedding application feeds it a
// media file it does not control.
//
// One binary serves every target: build.sh hardlinks it as mediainfo_<target>[-standalone], and
// LLVMFuzzerInitialize reads the target from argv[0] (fixed for the process, read-only afterwards):
//   mediainfo_auto      buffer API (Open_Buffer_*), format auto-detected as for any unknown file;
//   mediainfo_openfile  MediaInfo::Open(path) on a temp file (the mediainfo CLI's path: Reader_File,
//                       real seeking, per-format detection);
//   mediainfo_<fmt>     buffer API with the public File_ForceParser option set to that parser
//                       (names as accepted by SelectFromExtension in MediaInfo_File.cpp).
// Each input gets a fresh MediaInfo object; the per-instance options are identical for every input,
// so no state carries from one input to the next.
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <unistd.h>

#include "MediaInfo/MediaInfo.h"
#include "ZenLib/Ztring.h"

using namespace MediaInfoLib;

static const struct { const char *target; const wchar_t *parser; } kParsers[] = {
  {"mpeg4", L"Mpeg4"}, {"mpegts", L"MpegTs"}, {"mxf", L"Mxf"}, {"mk", L"Mk"},
  {"riff", L"Riff"}, {"mpegps", L"MpegPs"}, {"avc", L"Avc"}, {"hevc", L"Hevc"},
  {"adts", L"Adts"}, {"ac3", L"Ac3"}, {"jpeg", L"Jpeg"}, {"png", L"Png"},
  {"tiff", L"Tiff"}, {"ttml", L"TTML"}, {"aaf", L"Aaf"}, {"teletext", L"Teletext"},
  {"adm", L"Adm"}, {"ac4", L"Ac4"},
};
static const wchar_t *g_parser = nullptr; // nullptr = auto-detect
static bool g_open_file = false;

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv) {
  if (!argc || *argc < 1 || !argv || !*argv || !(*argv)[0])
    return 0;
  std::string name = (*argv)[0];
  size_t slash = name.rfind('/');
  if (slash != std::string::npos)
    name = name.substr(slash + 1);
  const std::string sa = "-standalone";
  if (name.size() > sa.size() && name.compare(name.size() - sa.size(), sa.size(), sa) == 0)
    name.resize(name.size() - sa.size());
  const std::string pre = "mediainfo_";
  if (name.compare(0, pre.size(), pre) == 0)
    name = name.substr(pre.size());
  if (name == "openfile")
    g_open_file = true;
  for (const auto &p : kParsers)
    if (name == p.target)
      g_parser = p.parser;
  return 0;
}

static void configure(MediaInfo &MI) {
  if (g_parser)
    MI.Option(__T("File_ForceParser"), g_parser);
  MI.Option(__T("ParseSpeed"), __T("1"));
}

static int open_file(const uint8_t *data, size_t size) {
  const char *tmp = getenv("TMPDIR");
  std::string path = std::string(tmp && *tmp ? tmp : "/tmp") + "/mediainfo-fuzz-XXXXXX";
  int fd = mkstemp(&path[0]);
  if (fd < 0)
    return 0;
  size_t off = 0;
  while (off < size) {
    ssize_t w = write(fd, data + off, size - off);
    if (w <= 0)
      break;
    off += (size_t)w;
  }
  close(fd);
  {
    MediaInfo MI;
    configure(MI);
    MI.Open(ZenLib::Ztring().From_Local(path.c_str()));
    MI.Option(__T("Inform"), __T("XML"));
    MI.Inform();
    MI.Close();
  }
  unlink(path.c_str());
  return 0;
}
extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (g_open_file)
    return open_file(data, size);
  MediaInfo MI;
  configure(MI);
  MI.Open_Buffer_Init(size, 0);
  size_t off = 0;
  int seeks = 0;
  while (off < size) {
    size_t chunk = size - off;
    if (chunk > 4096)
      chunk = 4096;
    size_t st = MI.Open_Buffer_Continue(data + off, chunk);
    off += chunk;
    if (st & 0x08) // Finished
      break;
    ZenLib::int64u go = MI.Open_Buffer_Continue_GoTo_Get();
    if (go != (ZenLib::int64u)-1) {
      // The parser asked to continue elsewhere in the file: honour it like a real reader would,
      // bounded so the harness itself cannot ping-pong forever.
      if (go >= size || ++seeks > 64)
        break;
      off = (size_t)go;
      MI.Open_Buffer_Init(size, go);
    }
  }
  MI.Open_Buffer_Finalize();
  MI.Option(__T("Inform"), __T("XML"));
  MI.Inform();
  MI.Close();
  return 0;
}
