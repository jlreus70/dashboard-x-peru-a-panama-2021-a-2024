---
name: fish-audio-api
description: Call the raw Fish Audio REST + WebSocket API directly (any language, edge runtimes, no SDK) — auth, endpoints, msgpack/JSON/multipart body rules, and the TTS streaming protocol.
---

# Fish Audio raw API

For languages/runtimes without an official SDK (Go, Rust, edge functions, etc.),
call the HTTP/WebSocket API directly. Base URL: `https://api.fish.audio`.
This was reconstructed from the official Python SDK's request-building code
(`fish-audio-sdk` 1.3.0 on PyPI), which wraps this same API — prefer it over
guessing endpoint paths or field names from memory.

## Auth

Every request needs:

```
Authorization: Bearer <FISH_API_KEY>
```

Get a key at https://fish.audio/app/api-keys.

## Body encoding

TTS and ASR requests are sent as **MessagePack**, not plain JSON:

```
Content-Type: application/msgpack
```

with the body packed with an ormsgpack-compatible encoder (any standard
MessagePack library works — field names/types below are exactly what's packed).
Voice-model create/update use `multipart/form-data` instead (see below).

## Text-to-speech — `POST /v1/tts`

Headers: `Authorization`, `Content-Type: application/msgpack`, and `model`
(one of `"s1"`, `"s2-pro"` — current; `"speech-1.5"`, `"speech-1.6"` — deprecated
but still accepted). Response body is a stream of raw audio bytes in the
requested `format` — read it as a byte stream, don't wait for a JSON envelope.

Request payload (msgpack map), all fields optional except `text`:

| field | type | default | notes |
|---|---|---|---|
| `text` | string | — | required |
| `format` | `"mp3"\|"wav"\|"pcm"\|"opus"` | `"mp3"` | |
| `sample_rate` | int | format default | Hz |
| `mp3_bitrate` | `64\|128\|192` | `128` | kbps |
| `opus_bitrate` | `-1000\|24\|32\|48\|64` | `32` | kbps, `-1000` = auto |
| `chunk_length` | int, 100–300 | `200` | chars per generation chunk |
| `normalize` | bool | `true` | clean input text |
| `latency` | `"normal"\|"balanced"` | `"balanced"` | balanced = faster |
| `reference_id` | string \| null | `null` | saved voice model id |
| `references` | list of `{audio: bytes, text: string}` | `[]` | instant-clone samples; `text` must exactly match what's spoken in `audio` |
| `prosody` | `{speed: float 0.5–2.0, volume: float -20..20}` \| null | `null` | |
| `top_p` | float 0–1 | `0.7` | |
| `temperature` | float 0–1 | `0.7` | |
| `max_new_tokens` | int | `1024` | |
| `repetition_penalty` | float | `1.2` | |
| `min_chunk_length` | int | `50` | |
| `condition_on_previous_chunks` | bool | `true` | |
| `early_stop_threshold` | float | `1.0` | |

## Real-time streaming — `wss://api.fish.audio/v1/tts/live`

Same `Authorization` and `model` headers as the HTTP endpoint (no `Content-Type`
needed; every WS frame is a MessagePack-packed binary message).

**Client → server** frames, in order:

1. One `start` event carrying the same TTS fields as the HTTP body above (use
   `text: ""` — actual text comes from subsequent `text` events):
   ```
   {"event": "start", "request": { ...TTS fields, "text": "" }}
   ```
2. Zero or more `text` events as text becomes available:
   ```
   {"event": "text", "text": "next chunk of text"}
   ```
3. Optionally a `flush` event to force synthesis of buffered text immediately:
   ```
   {"event": "flush"}
   ```
4. A `stop` event to end the session:
   ```
   {"event": "stop"}
   ```

**Server → client** frames:

- `{"event": "audio", "audio": <bytes>}` — an audio chunk; concatenate in
  arrival order.
- `{"event": "finish", "reason": "stop"}` — normal end, stop reading.
- `{"event": "finish", "reason": "error"}` — stream failed; treat as an error.

Unrecognized event types on either side should be ignored, not treated as fatal.

## Speech-to-text — `POST /v1/asr`

Headers: `Authorization`, `Content-Type: application/msgpack`.

Request body:

```
{"audio": <bytes>, "language": "en", "ignore_timestamps": false}
```

`language` is optional (auto-detected if omitted). `ignore_timestamps: false`
(the default you want) returns per-segment timestamps; set `true` to skip them.

Response (JSON):

```json
{
  "text": "full transcription",
  "duration": 12345.0,
  "segments": [{"text": "...", "start": 0.0, "end": 2.3}]
}
```

`duration` is in **milliseconds**. `segments` is `[]` when
`ignore_timestamps: true` was sent.

Input audio: WAV/PCM (16-bit, mono) or MP3 (mono).

## Voice / model management

All under `/model`, `Authorization` header only (no special `Content-Type` for
GET/DELETE).

- `GET /model` — list/search. Query params: `page_size` (default 10),
  `page_number` (default 1, 1-indexed), `title`, `tag` (repeatable or
  comma-joined), `self` (bool, only your own voices), `author_id`, `language`,
  `title_language`, `sort_by` (`"task_count"` default or `"created_at"`).
  Response: `{"total": int, "items": [Voice, ...]}`.
- `GET /model/{id}` — single voice. Response is a `Voice` object (see below).
- `POST /model` — create/clone a voice. **multipart/form-data**, not msgpack:
  form fields `title` (string, required), `description`, `visibility`
  (`"public"|"unlist"|"private"`, default `"private"`), `type` (`"tts"`),
  `train_mode` (`"fast"`, only supported value), `texts[]` (transcript per
  sample), `tags[]`, `enhance_audio_quality` (bool, default `true`); files:
  `voices` (repeatable — one or more training-sample audio files) and optional
  `cover_image`.
- `PATCH /model/{id}` — update metadata. multipart form: any of `title`,
  `description`, `visibility`, `tags[]`, optional `cover_image` file.
- `DELETE /model/{id}` — delete a voice.

`Voice` object fields: `_id` (use as `reference_id` in TTS), `type`
(`"svc"|"tts"`), `title`, `description`, `cover_image`, `train_mode`, `state`
(`"created"|"training"|"trained"|"failed"`), `tags[]`, `samples[]`,
`created_at`, `updated_at`, `languages[]`, `visibility`, `lock_visibility`,
`like_count`, `mark_count`, `shared_count`, `task_count`, `liked`, `marked`,
`author {_id, nickname, avatar}`.

## Account / billing

- `GET /wallet/self/api-credit` — optional query `check_free_credit` (bool).
  Response: `{"_id", "user_id", "credit" (decimal), "created_at", "updated_at", "has_phone_sha256"?, "has_free_credit"?}`.
- `GET /wallet/self/package` — response:
  `{"_id", "user_id", "type", "total" (int), "balance" (int), "created_at", "updated_at", "finished_at"?}`
  (`finished_at` is `null` while the package is still active).

## Errors

JSON error bodies typically look like `{"message": "..."}` or `{"detail": "..."}`.
Map status codes as:

| status | meaning |
|---|---|
| 401 | authentication failed — bad/missing API key |
| 403 | permission denied |
| 404 | resource not found |
| 429 | rate limited — back off and retry |
| 5xx | server error — safe to retry with backoff |
| other non-2xx | generic API error, read `message`/`detail` from body |

## Developer Program (optional)

Requests may include a `developer-id` header to attribute usage/commission under
Fish Audio's Developer Program (https://docs.fish.audio/developer-plan). Omit it
unless the user is specifically enrolled and asks for it.
