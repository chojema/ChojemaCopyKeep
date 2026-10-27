#include "image.h"
#include <shlwapi.h>
#include <algorithm>
#include <cstring>
#include <stdexcept>

namespace copykeep {
namespace {
const CLSID png_encoder = {0x557cf406,0x1a04,0x11d3,{0x9a,0x73,0x00,0x00,0xf8,0x1e,0xf3,0x2e}};
void check_image(Gdiplus::Bitmap& bitmap) {
    if (bitmap.GetLastStatus() != Gdiplus::Ok || !bitmap.GetWidth() || !bitmap.GetHeight() ||
        static_cast<unsigned long long>(bitmap.GetWidth()) * bitmap.GetHeight() > max_pixels)
        throw std::runtime_error("Image dimensions exceed limit");
}
Image encode(Gdiplus::Bitmap& bitmap) {
    check_image(bitmap);
    IStream* stream = nullptr;
    if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) throw std::runtime_error("Image stream failed");
    Image out;
    if (bitmap.Save(stream, &png_encoder, nullptr) != Gdiplus::Ok) { stream->Release(); throw std::runtime_error("PNG encoding failed"); }
    STATSTG stat{}; stream->Stat(&stat, STATFLAG_NONAME);
    if (stat.cbSize.QuadPart > 32ull * 1024 * 1024) { stream->Release(); throw std::runtime_error("Image exceeds limit"); }
    HGLOBAL memory = nullptr; GetHGlobalFromStream(stream, &memory);
    const auto* data = static_cast<const unsigned char*>(GlobalLock(memory));
    if (data) { out.png.assign(data, data + stat.cbSize.LowPart); GlobalUnlock(memory); }
    out.width = static_cast<int>(bitmap.GetWidth()); out.height = static_cast<int>(bitmap.GetHeight());
    stream->Release();
    if (out.png.empty()) throw std::runtime_error("PNG buffer failed");
    return out;
}
struct Decoder {
    IStream* stream = nullptr;
    std::unique_ptr<Gdiplus::Bitmap> bitmap;
    explicit Decoder(const Bytes& bytes) {
        if (bytes.empty() || bytes.size() > 32u * 1024 * 1024) throw std::runtime_error("Invalid PNG size");
        stream = SHCreateMemStream(bytes.data(), static_cast<UINT>(bytes.size()));
        if (!stream) throw std::runtime_error("PNG stream failed");
        bitmap.reset(Gdiplus::Bitmap::FromStream(stream, FALSE));
        try { check_image(*bitmap); } catch (...) { bitmap.reset(); stream->Release(); stream = nullptr; throw; }
    }
    ~Decoder() { bitmap.reset(); if (stream) stream->Release(); }
};
}
Image from_bitmap(HBITMAP source) {
    BITMAP info{};
    if (!source || !GetObjectW(source, sizeof(info), &info) ||
        static_cast<unsigned long long>(info.bmWidth) * std::abs(info.bmHeight) > max_pixels)
        throw std::runtime_error("Bitmap exceeds limit");
    Gdiplus::Bitmap bitmap(source, nullptr); return encode(bitmap);
}
Image from_png(const Bytes& bytes) {
    Decoder decoder(bytes);
    return {bytes, static_cast<int>(decoder.bitmap->GetWidth()), static_cast<int>(decoder.bitmap->GetHeight())};
}
Bytes image_dib(const Bytes& png) {
    Decoder decoder(png);
    auto& bitmap = *decoder.bitmap;
    const int width = static_cast<int>(bitmap.GetWidth()), height = static_cast<int>(bitmap.GetHeight());
    BITMAPV5HEADER header{};
    header.bV5Size = sizeof(header); header.bV5Width = width; header.bV5Height = -height;
    header.bV5Planes = 1; header.bV5BitCount = 32; header.bV5Compression = BI_BITFIELDS;
    header.bV5SizeImage = width * height * 4;
    header.bV5RedMask = 0x00ff0000; header.bV5GreenMask = 0x0000ff00; header.bV5BlueMask = 0x000000ff; header.bV5AlphaMask = 0xff000000;
    header.bV5CSType = LCS_sRGB;
    Bytes out(sizeof(header) + static_cast<size_t>(header.bV5SizeImage));
    std::memcpy(out.data(), &header, sizeof(header));
    Gdiplus::BitmapData pixels{};
    Gdiplus::Rect rect(0, 0, width, height);
    if (bitmap.LockBits(&rect, Gdiplus::ImageLockModeRead, PixelFormat32bppARGB, &pixels) != Gdiplus::Ok)
        throw std::runtime_error("Image pixels unavailable");
    for (int y = 0; y < height; ++y)
        std::memcpy(out.data() + sizeof(header) + static_cast<size_t>(y) * width * 4,
                    static_cast<unsigned char*>(pixels.Scan0) + static_cast<ptrdiff_t>(y) * pixels.Stride, static_cast<size_t>(width) * 4);
    bitmap.UnlockBits(&pixels); return out;
}
HBITMAP thumbnail(const Bytes& png, int width, int height) {
    Decoder decoder(png);
    Gdiplus::Bitmap previewImage(width, height, PixelFormat32bppARGB);
    Gdiplus::Graphics graphics(&previewImage);
    graphics.Clear(Gdiplus::Color(255, 246, 248, 251));
    graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    double ratio = std::min(static_cast<double>(width) / decoder.bitmap->GetWidth(), static_cast<double>(height) / decoder.bitmap->GetHeight());
    int w = std::max(1, static_cast<int>(decoder.bitmap->GetWidth() * ratio));
    int h = std::max(1, static_cast<int>(decoder.bitmap->GetHeight() * ratio));
    graphics.DrawImage(decoder.bitmap.get(), (width-w)/2, (height-h)/2, w, h);
    HBITMAP out = nullptr; previewImage.GetHBITMAP(Gdiplus::Color(255,255,255,255), &out); return out;
}
bool save_bitmap(HBITMAP bitmap, const std::filesystem::path& path) {
    Gdiplus::Bitmap image(bitmap, nullptr); return image.Save(path.c_str(), &png_encoder, nullptr) == Gdiplus::Ok;
}
Image test_image() {
    Gdiplus::Bitmap bitmap(320, 180, PixelFormat32bppARGB);
    Gdiplus::Graphics graphics(&bitmap);
    graphics.Clear(Gdiplus::Color(255, 230, 239, 252));
    Gdiplus::SolidBrush brush(Gdiplus::Color(255, 48, 99, 191));
    graphics.FillEllipse(&brush, 100, 30, 120, 120);
    return encode(bitmap);
}
}
