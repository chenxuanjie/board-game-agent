#include "speech_to_text_windows_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <sapi.h>
#include <windows.h>

#include <iostream>
#include <sstream>
#include <string>
#include <utility>

namespace speech_to_text_windows {

namespace {

std::string EscapeJson(const std::string &value) {
  std::string escaped;
  escaped.reserve(value.size());

  static constexpr char hex[] = "0123456789abcdef";
  for (unsigned char character : value) {
    switch (character) {
    case '\\':
      escaped += "\\\\";
      break;
    case '"':
      escaped += "\\\"";
      break;
    case '\b':
      escaped += "\\b";
      break;
    case '\f':
      escaped += "\\f";
      break;
    case '\n':
      escaped += "\\n";
      break;
    case '\r':
      escaped += "\\r";
      break;
    case '\t':
      escaped += "\\t";
      break;
    default:
      if (character < 0x20) {
        escaped += "\\u00";
        escaped += hex[(character >> 4) & 0x0f];
        escaped += hex[character & 0x0f];
      } else {
        escaped.push_back(static_cast<char>(character));
      }
      break;
    }
  }
  return escaped;
}

std::string WideToUtf8(const wchar_t *value) {
  if (value == nullptr || *value == L'\0') {
    return {};
  }

  const int required =
      WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  if (required <= 1) {
    return {};
  }

  std::string result(static_cast<size_t>(required), '\0');
  const int converted = WideCharToMultiByte(
      CP_UTF8, 0, value, -1, result.data(), required, nullptr, nullptr);
  if (converted <= 0) {
    return {};
  }
  result.resize(static_cast<size_t>(converted - 1));
  return result;
}

std::string HResultToString(HRESULT status) {
  std::ostringstream stream;
  stream << "HRESULT 0x" << std::hex << static_cast<unsigned long>(status);
  return stream.str();
}

std::string ExtractRecognitionText(ISpRecoResult *result) {
  if (result == nullptr) {
    return {};
  }

  LPWSTR text = nullptr;
  const HRESULT status = result->GetText(static_cast<ULONG>(SP_GETWHOLEPHRASE),
                                         static_cast<ULONG>(SP_GETWHOLEPHRASE),
                                         TRUE, &text, nullptr);
  if (FAILED(status) || text == nullptr) {
    return {};
  }

  const std::string utf8 = WideToUtf8(text);
  CoTaskMemFree(text);
  return utf8;
}

} // namespace

void SpeechToTextWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "speech_to_text_windows",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<SpeechToTextWindowsPlugin>();
  plugin->m_channel = std::move(channel);

  plugin->m_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

SpeechToTextWindowsPlugin::SpeechToTextWindowsPlugin()
    : m_cpRecognizer(nullptr), m_cpRecoContext(nullptr),
      m_cpRecoGrammar(nullptr), m_cpAudio(nullptr), m_initialized(false),
      m_listening(false), m_com_initialized(false),
      m_events([this](auto token) { HandleSpeechEvents(token); }) {
  std::cout << "SpeechToTextWindowsPlugin created" << std::endl;
  const HRESULT status = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  m_com_initialized = SUCCEEDED(status);
}

SpeechToTextWindowsPlugin::~SpeechToTextWindowsPlugin() {
  std::cout << "SpeechToTextWindowsPlugin destroyed" << std::endl;

  m_events.AssertOwner();
  Stop(nullptr);
  ReleaseSapiObjects();
  m_initialized = false;

  if (m_com_initialized) {
    CoUninitialize();
  }
}

void SpeechToTextWindowsPlugin::ReleaseRecognitionContext() {
  m_events.AssertOwner();
  m_events.Invalidate();
  if (m_cpRecoContext != nullptr) {
    // Unregister SAPI's asynchronous notifications before destroying the
    // window.
    const HRESULT status = m_cpRecoContext->SetNotifySink(nullptr);
    if (FAILED(status)) {
      std::cerr << "Unable to detach SAPI notifications: "
                << HResultToString(status) << std::endl;
    }
  }
  if (m_cpRecoGrammar != nullptr) {
    m_cpRecoGrammar->Release();
    m_cpRecoGrammar = nullptr;
  }
  if (m_cpRecoContext != nullptr) {
    m_cpRecoContext->Release();
    m_cpRecoContext = nullptr;
  }
}

void SpeechToTextWindowsPlugin::ReleaseSapiObjects() {
  ReleaseRecognitionContext();
  if (m_cpRecognizer != nullptr) {
    m_cpRecognizer->Release();
    m_cpRecognizer = nullptr;
  }
  if (m_cpAudio != nullptr) {
    m_cpAudio->Release();
    m_cpAudio = nullptr;
  }
}

void SpeechToTextWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  m_events.AssertOwner();
  const std::string &method_name = method_call.method_name();
  std::cout << "Method called: " << method_name << std::endl;

  if (method_name == "hasPermission") {
    result->Success(flutter::EncodableValue(true));
  } else if (method_name == "initialize") {
    Initialize(method_call, std::move(result));
  } else if (method_name == "listen") {
    Listen(method_call, std::move(result));
  } else if (method_name == "stop") {
    Stop(std::move(result));
  } else if (method_name == "cancel") {
    Cancel(std::move(result));
  } else if (method_name == "locales") {
    GetLocales(std::move(result));
  } else {
    result->NotImplemented();
  }
}

void SpeechToTextWindowsPlugin::Initialize(
    const flutter::MethodCall<flutter::EncodableValue> & /*method_call*/,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  m_events.AssertOwner();

  if (m_initialized) {
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (!m_com_initialized || !m_events.handle()) {
    result->Success(flutter::EncodableValue(false));
    return;
  }
  std::cout << "Initializing SAPI speech recognition..." << std::endl;
  HRESULT status = S_OK;

  status = CoCreateInstance(CLSID_SpInprocRecognizer, nullptr,
                            CLSCTX_INPROC_SERVER, IID_ISpRecognizer,
                            reinterpret_cast<void **>(&m_cpRecognizer));
  if (FAILED(status)) {
    std::cout << "Failed to create speech recognizer: "
              << HResultToString(status) << std::endl;
    ReleaseSapiObjects();
    result->Success(flutter::EncodableValue(false));
    return;
  }

  status =
      CoCreateInstance(CLSID_SpMMAudioIn, nullptr, CLSCTX_INPROC_SERVER,
                       IID_ISpAudio, reinterpret_cast<void **>(&m_cpAudio));
  if (FAILED(status)) {
    std::cout << "Failed to create audio input: " << HResultToString(status)
              << std::endl;
    ReleaseSapiObjects();
    result->Success(flutter::EncodableValue(false));
    return;
  }

  status = m_cpRecognizer->SetInput(m_cpAudio, TRUE);
  if (FAILED(status)) {
    std::cout << "Failed to set audio input: " << HResultToString(status)
              << std::endl;
    ReleaseSapiObjects();
    result->Success(flutter::EncodableValue(false));
    return;
  }

  status = CreateRecognitionContext();
  if (FAILED(status)) {
    ReleaseSapiObjects();
    result->Success(flutter::EncodableValue(false));
    return;
  }
  m_initialized = true;
  result->Success(flutter::EncodableValue(true));
}

HRESULT SpeechToTextWindowsPlugin::CreateRecognitionContext() {
  m_events.AssertOwner();
  HRESULT status = m_cpRecognizer->CreateRecoContext(&m_cpRecoContext);
  if (FAILED(status)) {
    std::cout << "Failed to create recognition context: "
              << HResultToString(status) << std::endl;
    ReleaseRecognitionContext();
    return status;
  }

  const ULONGLONG event_interest =
      SPFEI(SPEI_RECOGNITION) | SPFEI(SPEI_HYPOTHESIS) |
      SPFEI(SPEI_SOUND_START) | SPFEI(SPEI_SOUND_END);
  status = m_cpRecoContext->SetInterest(event_interest, event_interest);
  if (FAILED(status)) {
    std::cout << "Failed to configure recognition events: "
              << HResultToString(status) << std::endl;
    ReleaseRecognitionContext();
    return status;
  }

  status = m_cpRecoContext->CreateGrammar(0, &m_cpRecoGrammar);
  if (FAILED(status)) {
    std::cout << "Failed to create grammar: " << HResultToString(status)
              << std::endl;
    ReleaseRecognitionContext();
    return status;
  }

  status = m_cpRecoGrammar->LoadDictation(nullptr, SPLO_STATIC);
  if (FAILED(status)) {
    std::cout << "Failed to load dictation grammar: " << HResultToString(status)
              << std::endl;
    ReleaseRecognitionContext();
    return status;
  }

  return S_OK;
}

void SpeechToTextWindowsPlugin::Listen(
    const flutter::MethodCall<flutter::EncodableValue> & /*method_call*/,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  m_events.AssertOwner();
  if (!m_initialized) {
    result->Error("NOT_INITIALIZED", "Speech recognition not initialized");
    return;
  }
  if (m_listening) {
    result->Success(flutter::EncodableValue(true));
    return;
  }
  HRESULT status = S_OK;
  if (!m_cpRecoContext)
    status = CreateRecognitionContext();
  if (SUCCEEDED(status)) {
    const auto token = m_events.BeginSession();
    status = m_cpRecoContext->SetNotifyWindowMessage(
        m_events.handle(), PlatformEventWindow::kEventMessage, token, 0);
  }
  if (SUCCEEDED(status)) {
    status = m_cpRecoGrammar->SetDictationState(SPRS_ACTIVE);
  }
  if (FAILED(status)) {
    ReleaseRecognitionContext();
    SendError("Unable to activate dictation: " + HResultToString(status));
    result->Success(flutter::EncodableValue(false));
    return;
  }
  m_listening = true;
  SendStatus("listening");
  result->Success(flutter::EncodableValue(true));
}

void SpeechToTextWindowsPlugin::HandleSpeechEvents(
    PlatformEventWindow::Token token) {
  m_events.AssertOwner();
  if (!m_events.IsCurrent(token) || !m_listening || !m_cpRecoContext)
    return;
  // Bound work per window message so speech cannot monopolize the UI thread.
  for (int count = 0; count < 32; ++count) {
    SPEVENT event{};
    ULONG fetched = 0;
    const HRESULT status = m_cpRecoContext->GetEvents(1, &event, &fetched);
    if (FAILED(status)) {
      Stop(nullptr);
      SendError("SAPI event loop failed: " + HResultToString(status));
      return;
    }
    if (fetched == 0)
      return;
    switch (event.eEventId) {
    case SPEI_RECOGNITION:
    case SPEI_HYPOTHESIS: {
      const std::string text = ExtractRecognitionText(
          reinterpret_cast<ISpRecoResult *>(event.lParam));
      if (!text.empty()) {
        SendTextRecognition(text, event.eEventId == SPEI_RECOGNITION);
      }
      break;
    }
    case SPEI_SOUND_START:
      SendStatus("soundDetected");
      break;
    case SPEI_SOUND_END:
      SendStatus("soundEnded");
      break;
    default:
      break;
    }
    // Release every SAPI payload, including unexpected event types.
    if (event.elParamType == SPET_LPARAM_IS_TOKEN ||
        event.elParamType == SPET_LPARAM_IS_OBJECT) {
      if (event.lParam)
        reinterpret_cast<IUnknown *>(event.lParam)->Release();
    } else if (event.elParamType == SPET_LPARAM_IS_POINTER ||
               event.elParamType == SPET_LPARAM_IS_STRING) {
      CoTaskMemFree(reinterpret_cast<void *>(event.lParam));
    }
    if (!m_events.IsCurrent(token))
      return;
  }
  if (!m_events.Post(token)) {
    Stop(nullptr);
    SendError("Unable to schedule speech events");
  }
}

void SpeechToTextWindowsPlugin::Stop(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  m_events.AssertOwner();
  const bool was_listening = m_listening;
  m_listening = false;
  m_events.Invalidate();
  HRESULT status = S_OK;
  if (m_cpRecoGrammar) {
    status = m_cpRecoGrammar->SetDictationState(SPRS_INACTIVE);
  }
  // New sessions get a new SAPI queue, not just a new notification token.
  // Neither old window messages nor unread recognition results can leak in.
  ReleaseRecognitionContext();
  if (was_listening)
    SendStatus("notListening");
  if (FAILED(status))
    SendError("Unable to stop dictation: " + HResultToString(status));
  if (result)
    result->Success(flutter::EncodableValue(nullptr));
}

void SpeechToTextWindowsPlugin::Cancel(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  Stop(std::move(result));
}

void SpeechToTextWindowsPlugin::GetLocales(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  flutter::EncodableList locales;
  locales.push_back(flutter::EncodableValue("en-US:English (United States)"));
  locales.push_back(flutter::EncodableValue("en-GB:English (United Kingdom)"));
  locales.push_back(flutter::EncodableValue("zh-CN:Chinese (Simplified)"));
  result->Success(flutter::EncodableValue(locales));
}

void SpeechToTextWindowsPlugin::SendTextRecognition(const std::string &text,
                                                    bool is_final) {
  m_events.AssertOwner();
  if (!m_channel) {
    return;
  }

  // speech_to_text 7.x requires an alternates array. The hosted Windows
  // plugin only sent recognizedWords/finalResult, which made JSON parsing fail
  // before the app's onResult callback could run.
  const std::string json_result =
      "{\"alternates\":[{\"recognizedWords\":\"" + EscapeJson(text) +
      "\",\"recognizedPhrases\":null,\"confidence\":-1.0}]," +
      "\"finalResult\":" + (is_final ? "true" : "false") + "}";

  m_channel->InvokeMethod(
      "textRecognition",
      std::make_unique<flutter::EncodableValue>(json_result));
}

void SpeechToTextWindowsPlugin::SendError(const std::string &error) {
  m_events.AssertOwner();
  if (!m_channel) {
    return;
  }

  const std::string json_error =
      "{\"errorMsg\":\"" + EscapeJson(error) + "\",\"permanent\":false}";
  m_channel->InvokeMethod(
      "notifyError", std::make_unique<flutter::EncodableValue>(json_error));
}

void SpeechToTextWindowsPlugin::SendStatus(const std::string &status) {
  m_events.AssertOwner();
  if (!m_channel) {
    return;
  }
  m_channel->InvokeMethod("notifyStatus",
                          std::make_unique<flutter::EncodableValue>(status));
}

} // namespace speech_to_text_windows

extern "C" __declspec(dllexport) void
SpeechToTextWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  speech_to_text_windows::SpeechToTextWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
