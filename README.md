# HearSub

Live bilingual subtitles for macOS.

HearSub sits in the menu bar, listens to your microphone or Mac audio, and shows a compact two-line subtitle overlay above whatever app you are using. It is built for meetings, calls, livestreams, videos, online classes, and any situation where you want to hear one language while reading another.

[中文文档](README.zh-CN.md) · [Releases](https://github.com/lqy007700/HearSub/releases) · [Telegram @hearsub](https://t.me/+jCiQnWqrbLVjZTgx)

## What It Does

- Captures audio from a microphone or system audio on macOS.
- Transcribes speech with Apple's SpeechAnalyzer and SpeechTranscriber APIs.
- Displays live subtitles in a floating overlay that stays out of your main workflow.
- Shows source text, translated text, or both.
- Supports multiple selected input sources, each with optional source and subtitle language overrides.
- Translates through an OpenAI-compatible Chat Completions endpoint.
- Can prepare Apple on-device translation resources when Apple Translation is selected in settings.
- Uses Silero VAD with ONNX Runtime to detect speech boundaries and reduce noisy subtitle commits.
- Keeps a transcript history and can export transcript text.
- Summarizes transcripts with Apple Intelligence on macOS versions that support it.
- Includes menu bar controls, advanced settings, launch-at-login, and Sparkle-based app updates.

## Current Language Support

Speech input languages are intentionally limited to the languages available through Apple's SpeechAnalyzer/SpeechTranscriber path:

- English
- Chinese (Simplified)
- Cantonese
- Spanish
- German
- Japanese
- French
- Italian
- Korean
- Portuguese

Subtitle output language choices include common interface languages such as English, Chinese (Simplified), Spanish, German, Japanese, French, Korean, Arabic, Portuguese, and Russian. Actual translation quality and language coverage depend on the translation backend you configure.

## Translation Backend

HearSub defaults to an OpenAI-compatible translation backend. In **Settings -> Translation**, configure:

- Base URL, for example `https://api.openai.com/v1` or another compatible endpoint.
- API key.
- Model name.

The app can fetch available models and test the connection from the settings window. Translation requests are sent only to the endpoint you configure.

## Privacy

- HearSub has no built-in analytics, telemetry, account system, or project-owned backend.
- Audio capture and speech recognition are handled locally through Apple's macOS APIs.
- The Silero VAD model runs locally through ONNX Runtime.
- Subtitle text is sent to your configured OpenAI-compatible translation service when that backend is used.
- Transcript data and app settings are stored locally under the HearSub app support directory.

## Requirements

- macOS 26 or newer for the current SpeechAnalyzer/SpeechTranscriber transcription path.
- macOS 15 or newer for system audio capture.
- A microphone permission grant when using microphone input.
- An audio capture permission grant when capturing Mac audio.
- An OpenAI-compatible translation endpoint for live translated subtitles.
- Full Xcode installation for building from source.

Some features are version-gated by macOS:

- Transcript summarization requires macOS 26 or newer.
- Apple on-device translation availability depends on the language pair and installed system language resources.

## Build From Source

```bash
git clone git@github.com:lqy007700/HearSub.git
cd HearSub
open HearSub.xcodeproj
```

Or build from the terminal:

```bash
xcodebuild -project HearSub.xcodeproj -scheme HearSub -configuration Debug build
```

The project uses Swift Package Manager dependencies through the Xcode project. A full Xcode toolchain is required; Command Line Tools alone are not enough for app builds.

## Project Layout

```text
Sources/HearSubApp/        macOS app source
Tests/HearSubTests/        unit tests for settings, localization, language catalog, and subtitle heuristics
Assets.xcassets/           app icon assets
Config/Info.plist          app metadata, permissions, and Sparkle appcast configuration
docs/                      static GitHub Pages site
scripts/release.sh         release helper for version bumps and GitHub releases
```

## Release Notes

Tagged releases are built by the GitHub Actions release workflow. Release artifacts are published as `.dmg` installers with a Sparkle appcast.

## License

MIT
