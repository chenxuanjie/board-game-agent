# speech_to_text_windows

The Windows implementation of the `speech_to_text` plugin using the Windows
Speech API (SAPI) dictation recognizer.

This copy is kept in the application repository so it can remain compatible
with the current `speech_to_text` result protocol while retaining the upstream
plugin's SAPI architecture.

## Windows event ownership

SAPI objects are created, read and released on Flutter's platform COM apartment.
`ISpNotifySource::SetNotifyWindowMessage` posts to a message-only window on that
thread; no polling worker calls `MethodChannel`. Each dispatch handles at most
32 events before yielding to the Windows message loop. Stop/cancel invalidates
the session token and releases its recognition context; restart uses a new SAPI
queue. Stale notifications are ignored, including after window destruction.

Run the native thread/lifecycle regression (MSVC and initialized Flutter Windows
headers required) with `pwsh -NoProfile -File windows/test/run-tests.ps1` from
this package. It compiles the production translation unit and runs a real
Windows message-loop test; it does not package the app or test a microphone.


## Usage

See [speech_to_text](https://github.com/csdcorp/speech_to_text/blob/main/speech_to_text/README.md)

