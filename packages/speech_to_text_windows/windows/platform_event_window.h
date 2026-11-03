#ifndef SPEECH_TO_TEXT_WINDOWS_PLATFORM_EVENT_WINDOW_H_
#define SPEECH_TO_TEXT_WINDOWS_PLATFORM_EVENT_WINDOW_H_

#include <windows.h>

#include <atomic>
#include <cassert>
#include <cstdint>
#include <functional>
#include <string>
#include <utility>

namespace speech_to_text_windows {

// SAPI posts an opaque session token to this message-only window. Its window
// procedure runs on the creating (Flutter platform/COM apartment) thread.
// No worker waits for that thread, and posted messages never own raw pointers.
class PlatformEventWindow {
public:
  static constexpr UINT kEventMessage = WM_APP + 1;
  using Token = UINT_PTR;

  explicit PlatformEventWindow(std::function<void(Token)> on_event)
      : on_event_(std::move(on_event)), owner_(GetCurrentThreadId()) {
    class_name_ = L"BoardGameSpeechEvents." +
                  std::to_wstring(reinterpret_cast<std::uintptr_t>(this));
    WNDCLASSW window_class{};
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.lpfnWndProc = WindowProc;
    window_class.lpszClassName = class_name_.c_str();
    registered_ = RegisterClassW(&window_class) != 0;
    if (registered_) {
      window_ =
          CreateWindowExW(0, class_name_.c_str(), L"", 0, 0, 0, 0, 0,
                          HWND_MESSAGE, nullptr, window_class.hInstance, this);
    }
  }

  ~PlatformEventWindow() {
    AssertOwner();
    Invalidate();
    if (window_)
      DestroyWindow(window_);
    if (registered_) {
      UnregisterClassW(class_name_.c_str(), GetModuleHandleW(nullptr));
    }
  }

  PlatformEventWindow(const PlatformEventWindow &) = delete;
  PlatformEventWindow &operator=(const PlatformEventWindow &) = delete;

  HWND handle() const { return window_; }
  void AssertOwner() const { assert(GetCurrentThreadId() == owner_); }
  Token BeginSession() {
    AssertOwner();
    // Unique across instances too: a recycled HWND cannot accept an old token.
    static std::atomic<Token> next{1};
    token_ = next.fetch_add(1);
    return token_;
  }
  void Invalidate() {
    AssertOwner();
    token_ = 0;
  }
  bool IsCurrent(Token token) const {
    AssertOwner();
    return token != 0 && token == token_;
  }
  bool Post(Token token) const {
    AssertOwner();
    return window_ && PostMessageW(window_, kEventMessage, token, 0) != 0;
  }

private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam) {
    auto *self = reinterpret_cast<PlatformEventWindow *>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      self = static_cast<PlatformEventWindow *>(
          reinterpret_cast<CREATESTRUCTW *>(lparam)->lpCreateParams);
      SetWindowLongPtrW(window, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(self));
    }
    if (self && message == kEventMessage) {
      if (self->IsCurrent(wparam))
        self->on_event_(wparam);
      return 0;
    }
    if (message == WM_NCDESTROY) {
      SetWindowLongPtrW(window, GWLP_USERDATA, 0);
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }

  std::function<void(Token)> on_event_;
  DWORD owner_;
  std::wstring class_name_;
  bool registered_ = false;
  HWND window_ = nullptr;
  Token token_ = 0;
};

} // namespace speech_to_text_windows
#endif
