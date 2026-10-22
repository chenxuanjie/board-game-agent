# speech_to_text_windows releases

## Local compatibility fixes

* Emit the `alternates` result structure expected by `speech_to_text` 7.x.
* Escape recognized text and errors as valid JSON.
* Add the installed Simplified Chinese locale.
* Join the recognition worker before releasing SAPI objects.

## 1.0.0+beta.1

### New
* First implementation of Windows for speech_to_text
