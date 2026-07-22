---
name: fish-audio-sdk
description: Write correct Fish Audio SDK code (Python `fishaudio` / legacy `fish_audio_sdk`, JS `fish-audio` / legacy `fish-audio-sdk`) for text-to-speech, speech-to-text, voice cloning, and account/billing calls — exact method signatures, defaults, and exception types.
---

# Fish Audio SDK

Fish Audio (https://fish.audio, docs at https://docs.fish.audio) provides TTS, ASR
(speech-to-text), and voice-cloning APIs. There are official SDKs for Python and
JavaScript/TypeScript, each with a current package and a legacy/alternate package.
Content below was extracted directly from the published package sources
(`fish-audio-sdk` 1.3.0 on PyPI, `fish-audio` 0.1.0 and `fish-audio-sdk` 2025.11.29
on npm) — prefer it over guessing method names from memory.

Get an API key at https://fish.audio/app/api-keys and set `FISH_API_KEY` in the
environment (both SDKs read it automatically if `api_key` isn't passed explicitly).

## Python

### Which package

`pip install fish-audio-sdk` installs a single distribution that contains **two**
importable packages:

- `fishaudio` — **current, recommended.** `FishAudio` / `AsyncFishAudio` clients.
- `fish_audio_sdk` — legacy API (`Session`/`AsyncSession`, still works, no new
  features). Only use it if you're maintaining code already written against it.

Only write new code against `fishaudio`.

### Client

```python
from fishaudio import FishAudio, AsyncFishAudio

client = FishAudio(api_key="your_api_key")  # or omit and set FISH_API_KEY env var
# AsyncFishAudio(api_key=...) has the identical async surface (await + async for)

client.close()  # or use `with FishAudio(...) as client:` / `async with AsyncFishAudio(...)`
```

Constructor args: `api_key`, `base_url` (default `"https://api.fish.audio"`),
`timeout` (default `240.0` seconds), `httpx_client` (bring your own `httpx.Client`).

### Text-to-speech — `client.tts`

```python
from fishaudio.utils import play, save

audio: bytes = client.tts.convert(text="Hello, world!")   # full audio, blocks until done
save(audio, "output.mp3")
play(audio)

for chunk in client.tts.stream(text="Long content..."):    # AudioStream, iterate chunk-by-chunk
    send_to_websocket(chunk)
audio = client.tts.stream(text="Hello!").collect()          # same as convert()
```

Common kwargs on both `convert()` and `stream()` (all keyword-only):
`text`, `reference_id` (voice/model id string), `references` (list of
`ReferenceAudio` for on-the-fly cloning), `format` (`"mp3"|"wav"|"pcm"|"opus"`,
default `"mp3"`), `latency` (`"normal"|"balanced"`, default `"balanced"`),
`speed` (float multiplier, e.g. `1.5`), `config` (a `TTSConfig` for reuse across
calls), `model` (default `"s2-pro"`; other valid values `"s1"`, and deprecated
`"speech-1.5"`/`"speech-1.6"` which emit a `DeprecationWarning`).

```python
from fishaudio.types import TTSConfig, Prosody, ReferenceAudio

config = TTSConfig(
    prosody=Prosody(speed=1.2, volume=-5),   # speed 0.5-2.0, volume -20..20 dB
    reference_id="933563129e564b19a115bedd57b7406a",
    format="wav",
    latency="balanced",
)
audio1 = client.tts.convert(text="First message", config=config)
audio2 = client.tts.convert(text="Second message", config=config)  # reused config

# Instant voice cloning from a reference sample (no saved voice model needed)
with open("reference.wav", "rb") as f:
    audio = client.tts.convert(
        text="Cloned voice speaking",
        references=[ReferenceAudio(audio=f.read(), text="Text spoken in reference")],
    )
```

Real-time streaming (send text as it's generated, e.g. from an LLM; get audio back
as it's synthesized) — `client.tts.stream_websocket()`:

```python
def text_chunks():
    yield "Hello, "
    yield "this is "
    yield "streaming!"

with open("output.mp3", "wb") as f:
    for audio_chunk in client.tts.stream_websocket(text_chunks(), latency="balanced"):
        f.write(audio_chunk)
```

Takes an iterable of `str` (or `TextEvent`/`FlushEvent` for fine control), plus the
same `reference_id`/`references`/`format`/`latency`/`speed`/`config`/`model`
kwargs as `convert()`/`stream()`. Extra kwargs: `max_workers` (thread pool size for
the sender, default `10`), `ws_options` (a `WebSocketOptions(...)` — use e.g.
`keepalive_ping_timeout_seconds=60.0` for long-running generations that exceed the
default WS timeout).

### Speech-to-text — `client.asr`

```python
with open("audio.mp3", "rb") as f:
    result = client.asr.transcribe(audio=f.read(), language="en")  # language optional, auto-detected if omitted

print(result.text)          # full transcription
print(result.duration)      # milliseconds
for seg in result.segments: # empty if include_timestamps=False
    print(f"[{seg.start:.2f}s - {seg.end:.2f}s] {seg.text}")
```

`transcribe()` kwargs: `audio` (bytes, required), `language` (str, optional),
`include_timestamps` (bool, default `True`).

### Voice management — `client.voices`

```python
voices = client.voices.list(page_size=20, tags=["male", "english"])  # PaginatedResponse[Voice]
print(voices.total)
for v in voices.items:
    print(v.title, v.id)

voice = client.voices.get("voice_id_here")

with open("voice_sample.wav", "rb") as f:
    voice = client.voices.create(
        title="My Voice",
        voices=[f.read()],           # list of audio-sample bytes (multiple samples improve quality)
        description="Custom voice clone",
        tags=["custom", "english"],
        visibility="private",        # "public" | "unlist" | "private"
    )
audio = client.tts.convert(text="Using my saved voice", reference_id=voice.id)

client.voices.update("voice_id_here", title="Updated Title", visibility="public")
client.voices.delete("voice_id_here")
```

`list()` extra filters: `page_number`, `title`, `self_only` (bool), `author_id`,
`language`, `title_language`, `sort_by` (`"task_count"` default, or
`"created_at"`).

### Account — `client.account`

```python
credits = client.account.get_credits()
print(float(credits.credit))

package = client.account.get_package()
print(f"{package.balance}/{package.total}")
```

### Exceptions

```python
from fishaudio.exceptions import (
    FishAudioError,       # base class for everything below
    APIError,             # any non-2xx not covered by a specific class; has .status, .message, .body
    AuthenticationError,  # 401
    PermissionError,      # 403
    NotFoundError,        # 404
    RateLimitError,       # 429
    ServerError,          # 5xx
    WebSocketError,       # WS disconnect / stream error
    ValidationError,      # bad request payload
    DependencyError,      # optional extra (e.g. `play`/`save`) not installed
)

try:
    audio = client.tts.convert(text="Hello!")
except AuthenticationError:
    print("Invalid API key")
except RateLimitError:
    print("Rate limit exceeded")
except FishAudioError as e:
    print(f"API error: {e}")
```

`play()`/`save()` require the `utils` extra: `pip install fish-audio-sdk[utils]`.

## JavaScript / TypeScript

Two packages exist — pick one, don't mix:

- **`fish-audio`** (npm, official, current) — `FishAudioClient`. Prefer this for
  new code.
- **`fish-audio-sdk`** (npm, community-maintained, matches the older Python
  `Session` shape) — still fine, has WebSocket voice-cloning fixes for Node.

### `fish-audio` (recommended)

```typescript
import { FishAudioClient, play } from "fish-audio";

const fishAudio = new FishAudioClient({ apiKey: "your_api_key" }); // or FISH_API_KEY env var
// optional: { apiKey, baseUrl: "https://your-proxy-domain" }
```

Text-to-speech:

```typescript
const audio = await fishAudio.textToSpeech.convert({ text: "Hello, world!" }); // defaults to model "s2-pro"
await play(audio);

// with a specific voice
const request: TTSRequest = { text: "Hello, world!", reference_id: "your_model_id" };

// instant cloning with an in-request reference sample
const referenceAudio: ReferenceAudio = {
    audio: new File([audioBuffer], "audio_file_name"),
    text: "reference audio text",
};
const request2: TTSRequest = { text: "Hello, world!", references: [referenceAudio] };
```

Real-time WebSocket streaming:

```typescript
import { RealtimeEvents } from "fish-audio";

async function* makeTextStream() {
    yield "Hello from Fish Audio! ";
    yield "This is a realtime text-to-speech test.";
}

const connection = await fishAudio.textToSpeech.convertRealtime(
    { text: "", reference_id: "your_model_id" },  // text: "" — content comes from the stream
    makeTextStream(),
);

connection.on(RealtimeEvents.OPEN, () => console.log("opened"));
connection.on(RealtimeEvents.AUDIO_CHUNK, (chunk) => { /* Buffer/Uint8Array */ });
connection.on(RealtimeEvents.ERROR, (err) => console.error(err));
connection.on(RealtimeEvents.CLOSE, () => { /* flush collected chunks to disk */ });
```

Speech-to-text:

```typescript
import { createReadStream } from "fs";

const result = await fishAudio.speechToText.convert({
    audio: createReadStream(new URL("/path/to/audio/file")),
});
console.log(result.text, result.duration, result.segments);
```

Voices:

```typescript
await fishAudio.voices.ivc.create({ title: "cloned-voice-name", voices: [audioFile], cover_image: coverImageFile });
await fishAudio.voices.search();               // list/filter models
await fishAudio.voices.get("your_model_id");
await fishAudio.voices.update("your_model_id", { title: "new_title" });
await fishAudio.voices.delete("your_model_id");
```

Account:

```typescript
await fishAudio.user.get_api_credit();
await fishAudio.user.get_package();
```

### `fish-audio-sdk` (legacy/alternate)

```typescript
import { Session, TTSRequest, WebSocketSession, ASRRequest } from "fish-audio-sdk";

const session = new Session("your_api_key");
// optional custom endpoint / developer id: new Session(apiKey, baseUrl, developerId)
try {
    const writeStream = fs.createWriteStream("output.mp3");
    for await (const chunk of session.tts(new TTSRequest("Hello, world!"), { model: "speech-1.5" })) {
        writeStream.write(chunk);
    }
    writeStream.end();
} finally {
    session.close(); // always clean up — leaks HTTP connections otherwise
}
```

`TTSRequest(text, options)` options: `format` (`"wav"|"pcm"|"mp3"|"opus"`),
`mp3Bitrate` (`64|128|192`), `opusBitrate` (`-1000|24|32|48|64`), `sampleRate`,
`chunkLength` (`100`-`300`), `normalize`, `latency` (`"normal"|"balanced"`),
`referenceId`, `prosody: { speed, volume }`. Model header values:
`"speech-1.5"` (default), `"speech-1.6"`, `"agent-x0"`.

```typescript
const ws = new WebSocketSession("your_api_key");
try {
    const request = new TTSRequest("", { format: "mp3", latency: "balanced" });
    for await (const audioChunk of ws.tts(request, textStream())) { /* ... */ }
} finally {
    await ws.close();
}
```

ASR:

```typescript
const result = await session.asr(new ASRRequest(audioBuffer, "en", false)); // language, includeTimestamps
console.log(result.text, result.duration, result.segments);
```

Voice management: `session.createModel({...})`, `session.listModels({...})`,
`session.getModel(id)`, `session.updateModel(id, {...})`, `session.deleteModel(id)`.
Account: `session.getApiCredit()`, `session.getPackage()`.

Errors: `HttpCodeError` (has `.status`), `AuthenticationError`,
`PaymentRequiredError`, `NotFoundError`, `WebSocketError` — all imported from
`fish-audio-sdk`.

## Model selection (all SDKs)

Current models: `"s1"`, `"s2-pro"` (Python default). `"speech-1.5"` and
`"speech-1.6"` are deprecated — using them still works but the Python SDK emits a
`DeprecationWarning`; prefer `"s1"`/`"s2-pro"` in new code unless the user
explicitly asks for a specific legacy model.

## Audio format limits (both languages, same underlying API)

- ASR input: WAV/PCM (16-bit, mono) or MP3 (mono).
- TTS output: WAV/PCM (8/16/24/32/44.1kHz, default 44.1kHz, 16-bit mono); MP3
  (32/44.1kHz, default 44.1kHz, mono, bitrate 64/128/192kbps); Opus (48kHz mono,
  bitrate -1000 auto/24/32/48/64kbps).
