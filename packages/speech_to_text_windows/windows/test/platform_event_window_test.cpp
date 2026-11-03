#include "../platform_event_window.h"

#include <cstdlib>
#include <iostream>
#include <thread>
#include <vector>

using speech_to_text_windows::PlatformEventWindow;

void Check(bool condition) {
  if (!condition)
    std::abort();
}

void Pump() {
  MSG message{};
  // Tests are bounded too: a broken reschedule must fail instead of hanging CI.
  int remaining = 20000;
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
    Check(--remaining > 0);
    DispatchMessageW(&message);
  }
}

int main() {
  const DWORD platform_thread = GetCurrentThreadId();
  std::vector<PlatformEventWindow::Token> delivered;
  PlatformEventWindow events([&](auto token) {
    Check(GetCurrentThreadId() == platform_thread);
    delivered.push_back(token);
  });
  Check(events.handle() != nullptr);

  const auto first = events.BeginSession();
  const HWND window = events.handle();
  // Simulate SAPI's foreign-thread producer. It never calls Flutter or waits
  // for the platform thread to dispatch, so shutdown cannot form a join cycle.
  std::thread producer([=] {
    Check(PostMessageW(window, PlatformEventWindow::kEventMessage, first, 0));
  });
  producer.join();
  Check(delivered.empty());
  Pump();
  Check(delivered.size() == 1 && delivered.back() == first);

  // A stopped/cancelled/error session's queued events must not reach the next.
  Check(events.Post(first));
  events.Invalidate();
  Pump();
  Check(delivered.size() == 1);
  const auto second = events.BeginSession();
  Check(events.Post(first));
  Check(events.Post(second));
  Pump();
  Check(delivered.size() == 2 && delivered.back() == second);

  for (int cycle = 0; cycle < 1000; ++cycle) {
    const auto old = events.BeginSession();
    Check(events.Post(old));
    events.Invalidate();
    const auto current = events.BeginSession();
    Check(events.Post(current));
    Pump();
    Check(delivered.size() == static_cast<size_t>(cycle + 3));
    Check(delivered.back() == current);
  }

  int after_destroy = 0;
  HWND destroyed_window;
  PlatformEventWindow::Token destroyed_token;
  {
    PlatformEventWindow doomed([&](auto) { ++after_destroy; });
    destroyed_window = doomed.handle();
    Check(destroyed_window != nullptr);
    destroyed_token = doomed.BeginSession();
    Check(doomed.Post(destroyed_token));
  }
  // Pending notifications carry only a token, not a dangling plugin pointer.
  PostMessageW(destroyed_window, PlatformEventWindow::kEventMessage,
               destroyed_token, 0);
  Pump();
  Check(after_destroy == 0);
  {
    PlatformEventWindow replacement([&](auto) { ++after_destroy; });
    const auto token = replacement.BeginSession();
    Check(token != destroyed_token);
    Check(replacement.Post(destroyed_token));
    Pump();
    Check(after_destroy == 0);
    Check(replacement.Post(token));
    Pump();
    Check(after_destroy == 1);
  }
  std::cout
      << "Platform event dispatch: thread ownership, cancellation, restart, "
         "1000 cycles and destruction passed\n";
}
