// mayhem/selftest.cpp — functional oracle driver (built with the project's normal flags).
// Opens each file given on the command line with MediaInfo::Open and prints a fixed set of
// metadata fields, one "<file>|<stream>#<n>|<field>=<value>" line per non-empty field. test.sh
// diffs this against golden output, so a neutered library (no parse, wrong values) fails.
#include <cstdio>
#include <string>

#include "MediaInfo/MediaInfo.h"
#include "ZenLib/Ztring.h"

using namespace MediaInfoLib;

int main(int argc, char **argv) {
  static const struct { stream_t kind; const char *name; const char *fields[8]; } kinds[] = {
    {Stream_General, "General", {"Format", "FileSize", "Duration", "OverallBitRate", nullptr}},
    {Stream_Video, "Video", {"Format", "Width", "Height", "FrameRate", nullptr}},
    {Stream_Audio, "Audio", {"Format", "Channels", "SamplingRate", "BitDepth", "Duration", nullptr}},
    {Stream_Text, "Text", {"Format", "Duration", nullptr}},
    {Stream_Image, "Image", {"Format", "Width", "Height", "BitDepth", "ColorSpace", nullptr}},
  };
  int rc = 0;
  for (int a = 1; a < argc; a++) {
    MediaInfo MI;
    if (!MI.Open(ZenLib::Ztring().From_Local(argv[a]))) {
      printf("%s|open-failed\n", argv[a]);
      rc = 1;
      continue;
    }
    for (const auto &k : kinds) {
      size_t n = MI.Count_Get(k.kind);
      for (size_t i = 0; i < n; i++)
        for (const char *const *f = k.fields; *f; f++) {
          ZenLib::Ztring v = MI.Get(k.kind, i, ZenLib::Ztring().From_Local(*f));
          if (!v.empty())
            printf("%s|%s#%zu|%s=%s\n", argv[a], k.name, i, *f, v.To_Local().c_str());
        }
    }
    MI.Close();
  }
  return rc;
}
