#include "image_clipboard.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>

#include <cstring>
#include <limits>
#include <type_traits>
#include <utility>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Bytes = std::vector<uint8_t>;
using Memory =
    std::unique_ptr<std::remove_pointer_t<HGLOBAL>, decltype(&::GlobalFree)>;

template <class Value>
const Value* Get(const EncodableMap& args, const char* key) {
  const auto entry = args.find(EncodableValue(key));
  return entry == args.end() ? nullptr : std::get_if<Value>(&entry->second);
}

template <class Fill>
Memory MakeMemory(size_t size, Fill fill) {
  Memory memory(::GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, size), ::GlobalFree);
  if (memory) {
    if (void* data = ::GlobalLock(memory.get())) {
      const bool filled = fill(data);
      ::GlobalUnlock(memory.get());
      if (!filled) memory.reset();
    } else {
      memory.reset();
    }
  }
  return memory;
}

class Clipboard {
 public:
  explicit Clipboard(HWND window) : open_(::OpenClipboard(window) != FALSE) {}
  ~Clipboard() {
    if (open_) ::CloseClipboard();
  }

  bool Clear() const { return open_ && ::EmptyClipboard(); }

  bool Set(UINT format, Memory data) const {
    if (!format || !data || !::SetClipboardData(format, data.get())) {
      return false;
    }
    data.release();
    return true;
  }

 private:
  const bool open_;
};

Memory CopyBytes(const Bytes& bytes) {
  return MakeMemory(bytes.size(), [&](void* data) {
    std::memcpy(data, bytes.data(), bytes.size());
    return true;
  });
}

bool WriteBitmap(HWND window, const EncodableMap& args) {
  const auto* width = Get<int32_t>(args, "width");
  const auto* height = Get<int32_t>(args, "height");
  const auto* pixels = Get<Bytes>(args, "pixels");
  const auto* png = Get<Bytes>(args, "png");
  if (!width || !height || *width <= 0 || *height <= 0 || !pixels || !png ||
      png->empty() || uint64_t{4} * *width * *height != pixels->size() ||
      pixels->size() > std::numeric_limits<DWORD>::max() - sizeof(BITMAPV5HEADER)) {
    return false;
  }

  auto bitmap = MakeMemory(sizeof(BITMAPV5HEADER) + pixels->size(), [&](void* data) {
    auto* header = static_cast<BITMAPV5HEADER*>(data);
    header->bV5Size = sizeof(BITMAPV5HEADER);
    header->bV5Width = *width;
    header->bV5Height = -*height;
    header->bV5Planes = 1;
    header->bV5BitCount = 32;
    header->bV5Compression = BI_BITFIELDS;
    header->bV5SizeImage = static_cast<DWORD>(pixels->size());
    header->bV5RedMask = 0x00ff0000;
    header->bV5GreenMask = 0x0000ff00;
    header->bV5BlueMask = 0x000000ff;
    header->bV5AlphaMask = 0xff000000;
    header->bV5CSType = LCS_sRGB;
    header->bV5Intent = LCS_GM_IMAGES;
    auto* bgra = reinterpret_cast<uint8_t*>(header + 1);
    for (size_t offset = 0; offset < pixels->size(); offset += 4) {
      bgra[offset] = (*pixels)[offset + 2];
      bgra[offset + 1] = (*pixels)[offset + 1];
      bgra[offset + 2] = (*pixels)[offset];
      bgra[offset + 3] = (*pixels)[offset + 3];
    }
    return true;
  });
  const auto png_format = ::RegisterClipboardFormatW(L"PNG");
  auto png_memory = CopyBytes(*png);
  if (!bitmap && (!png_format || !png_memory)) return false;
  const Clipboard clipboard(window);
  if (!clipboard.Clear()) return false;
  const bool png_written = clipboard.Set(png_format, std::move(png_memory));
  const bool bitmap_written = clipboard.Set(CF_DIBV5, std::move(bitmap));
  return png_written || bitmap_written;
}

bool WriteFile(HWND window, const EncodableMap& args) {
  const auto* path = Get<std::string>(args, "path");
  if (!path || path->empty() || path->find('\0') != std::string::npos) {
    return false;
  }
  const int length = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                          path->c_str(), -1, nullptr, 0);
  if (length == 0) return false;
  auto drop = MakeMemory(sizeof(DROPFILES) +
                             (static_cast<size_t>(length) + 1) * sizeof(wchar_t),
                         [&](void* data) {
    auto* header = static_cast<DROPFILES*>(data);
    header->pFiles = sizeof(DROPFILES);
    header->fWide = TRUE;
    return ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path->c_str(),
                                -1, reinterpret_cast<wchar_t*>(header + 1),
                                length) == length;
  });
  if (!drop) return false;

  const auto* gif = Get<Bytes>(args, "gif");
  const Clipboard clipboard(window);
  if (!clipboard.Clear() || !clipboard.Set(CF_HDROP, std::move(drop))) {
    return false;
  }
  if (gif && !gif->empty()) {
    clipboard.Set(::RegisterClipboardFormatW(L"GIF"), CopyBytes(*gif));
    clipboard.Set(::RegisterClipboardFormatW(L"image/gif"), CopyBytes(*gif));
  }
  return true;
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<EncodableValue>>
RegisterImageClipboard(flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "piliauroranext/image_clipboard",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method != "writeBitmap" && method != "writeFile") {
      result->NotImplemented();
      return;
    }
    const auto* args = call.arguments()
        ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
    if (args && (method == "writeBitmap" ? WriteBitmap(window, *args)
                                         : WriteFile(window, *args))) {
      result->Success();
    } else {
      result->Error("clipboard_write_failed", "Could not copy image");
    }
  });
  return channel;
}
