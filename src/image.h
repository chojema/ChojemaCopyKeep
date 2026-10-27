#pragma once
#include "store.h"
#include <memory>
#include <objidl.h>
#include <gdiplus.h>

namespace copykeep {
constexpr unsigned long long max_pixels = 16ull * 1024 * 1024;
struct Image {
    Bytes png;
    int width = 0, height = 0;
};
Image from_bitmap(HBITMAP bitmap);
Image from_png(const Bytes& bytes);
Bytes image_dib(const Bytes& png);
HBITMAP thumbnail(const Bytes& png, int width, int height);
bool save_bitmap(HBITMAP bitmap, const std::filesystem::path& path);
Image test_image();
}
