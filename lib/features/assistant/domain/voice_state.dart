/// Lifecycle of the assistant.
///
/// idle      — user can tap to talk.
/// listening — microphone is active, transcribing the user.
/// thinking  — LLM is generating a response.
/// speaking  — TTS is reading the response aloud.
/// error     — something went wrong; UI surfaces it.
enum VoicePhase { idle, listening, thinking, speaking, error }
