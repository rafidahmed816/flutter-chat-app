# Chat App

A cross‑platform Flutter chat application that talks to a local LLM via Ollama. It renders assistant responses in Markdown, persists conversations using Sembast, and uses Riverpod for state management so drafts appear in the sidebar immediately while you type and while responses stream.

## Features

- Local LLM chat via [Ollama](https://ollama.com/)
- Markdown rendering for assistant messages (copy/select supported)
- Live sidebar updates as you type and during streaming (Riverpod)
- Conversation persistence with Sembast (rename and delete supported)
- Smooth, line‑by‑line fade/slide animation when loading history
- Multi‑platform ready (Android, iOS, Linux, macOS, Windows, Web)

## Architecture (Clean Architecture)

The app uses a lightweight clean architecture split:

- Presentation
  - `lib/app/screens/chat_screen.dart` – UI, animations, Markdown rendering
  - `lib/src/presentation/chat_controller.dart` – orchestrates chat + persistence
  - `lib/src/presentation/providers.dart` – Riverpod providers and state
- Domain
  - `lib/src/domain/entities/message.dart` – core message entity
  - `lib/src/domain/repositories/chat_repository.dart` – repository contract
- Data
  - `lib/src/data/chat_repository_impl.dart` – repository implementation
  - `lib/services/chat_database.dart` – Sembast database wrapper

This keeps UI, domain rules, and persistence concerns separate and testable.

## Requirements

- Flutter SDK (stable)
- Dart SDK (bundled with Flutter)
- Ollama installed locally and running
  - A compatible model available locally (default: `gemma3:4b`)

## Setup

1. Install Dart/Flutter dependencies

```sh
flutter pub get
```

1. Install and prepare Ollama (Linux/macOS/Windows)

```sh
# Install ollama (see https://ollama.com/download for your platform)
# Then pull a model used by this app:
ollama pull gemma3:4b

# Start Ollama (if not already running)
ollama serve
```

1. Run the app

```sh
# Desktop (Linux/macOS/Windows)
flutter run

# Android emulator (base URL handled automatically: 10.0.2.2:11434)
flutter run -d emulator-5554

# Web (uses http://localhost:11434)
flutter run -d chrome
```

Notes

- Android uses `http://10.0.2.2:11434` to reach your host machine.
- Desktop uses `http://127.0.0.1:11434` by default.
- Web uses `http://localhost:11434`; depending on your setup, you may need to allow CORS for the Ollama server or proxy requests.

## Usage

- Open the drawer to start a New Chat.
- Type your prompt; a draft conversation appears in the sidebar immediately.
- Send your message; the assistant’s streaming response updates both the main view and the sidebar in real time.
- Rename or delete a conversation from the sidebar (inline edit + actions).
- Assistant responses are rendered as Markdown and are selectable/copyable.

## Configuration

- Default model: `gemma3:4b`
  - Update the model name or `ModelOptions` where `chatStream` is called in `lib/app/screens/chat_screen.dart`.
- Base URL auto‑selects per platform:
  - Web: `http://localhost:11434`
  - Android emulator: `http://10.0.2.2:11434`
  - Desktop/iOS: `http://127.0.0.1:11434`
- App name: “Chat App” (see `lib/app/app.dart`)

## Project Structure

```text
lib/
	app/
		app.dart                  # MaterialApp, routes
		screens/
			chat_screen.dart        # UI, Markdown, animations
			onboarding_screen.dart
			splash_screen.dart
	assets/
		chat.png                  # App icon asset
	services/
		chat_database.dart        # Sembast database wrapper
	src/
		data/
			chat_repository_impl.dart
		domain/
			entities/
				message.dart
			repositories/
				chat_repository.dart
		presentation/
			chat_controller.dart
			providers.dart
```

## Troubleshooting

- Pubspec YAML errors
  - Ensure indentation is correct and run `flutter pub get` again.
- Cannot connect to Ollama
  - Verify the server is running and reachable at the expected base URL.
  - Android emulators must use `10.0.2.2` to reach host services.
- No responses / empty messages
  - Confirm the selected model is installed: `ollama pull gemma3:4b`.
- Reset conversation data
  - Sembast stores data in the app documents directory (platform‑specific). Deleting the `chat_history.db` file resets stored chats.

## License

This project is provided as‑is; add a license if you plan to distribute.
