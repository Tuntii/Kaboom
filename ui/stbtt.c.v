module ui

// stb_truetype 1.28 tek çeviri biriminde derlenir; yalnızca bu dosya include eder.
#define STB_TRUETYPE_IMPLEMENTATION
#include "@VMODROOT/third_party/stb/stb_truetype.h"

// Opak tutamaç; atlas.v içinde bayt dizisi olarak taşınır, boyutu atlas_test.v doğrular.
@[typedef]
pub struct C.stbtt_fontinfo {}

fn C.stbtt_InitFont(info &C.stbtt_fontinfo, data &u8, offset int) int
fn C.stbtt_ScaleForPixelHeight(info &C.stbtt_fontinfo, pixels f32) f32
fn C.stbtt_GetFontVMetrics(info &C.stbtt_fontinfo, ascent &int, descent &int, line_gap &int)
fn C.stbtt_FindGlyphIndex(info &C.stbtt_fontinfo, codepoint int) int
fn C.stbtt_GetGlyphHMetrics(info &C.stbtt_fontinfo, glyph int, advance &int, lsb &int)
fn C.stbtt_GetGlyphBitmapBox(info &C.stbtt_fontinfo, glyph int, sx f32, sy f32, x0 &int, y0 &int, x1 &int, y1 &int)
fn C.stbtt_MakeGlyphBitmap(info &C.stbtt_fontinfo, output &u8, out_w int, out_h int, out_stride int, sx f32, sy f32, glyph int)
fn C.stbtt_GetGlyphKernAdvance(info &C.stbtt_fontinfo, glyph1 int, glyph2 int) int
