#ifndef FLUTTER_PLUGIN_SPEECH_TO_TEXT_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_SPEECH_TO_TEXT_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>
#include <sapi.h>
#include <atomic>
#include <memory>
#include <mutex>
#include <thread>

namespace speech_to_text_windows {

class SpeechToTextWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SpeechToTextWindowsPlugin();
  virtual ~SpeechToTextWindowsPlugin();

  SpeechToTextWindowsPlugin(const SpeechToTextWindowsPlugin&) = delete;
  SpeechToTextWindowsPlugin& operator=(const SpeechToTextWindowsPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void Initialize(const flutter::MethodCall<flutter::EncodableValue> &method_call,
                 std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Listen(const flutter::MethodCall<flutter::EncodableValue> &method_call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Stop(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Cancel(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void GetLocales(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void SendTextRecognition(const std::string& text, bool is_final = false);
  void SendError(const std::string& error);
  void SendStatus(const std::string& status);
  void ReleaseSapiObjects();

  // SAPI Speech Recognition objects
  ISpRecognizer* m_cpRecognizer;
  ISpRecoContext* m_cpRecoContext;
  ISpRecoGrammar* m_cpRecoGrammar;
  ISpAudio* m_cpAudio;
  
  std::mutex m_mutex;
  bool m_initialized;
  std::atomic<bool> m_listening;
  bool m_com_initialized;
  std::thread m_recognition_thread;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> m_channel;
};

}  // namespace speech_to_text_windows

// C API for Flutter plugin registration
extern "C" __declspec(dllexport) void SpeechToTextWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#endif  // FLUTTER_PLUGIN_SPEECH_TO_TEXT_WINDOWS_PLUGIN_H_
