# ADR 0011: Mac inference through an OpenAI-compatible local server, and mDNS advertising

- Status: accepted
- Date: 2026-11-01

## Context

The gateway needs a model on the Mac. Gemma 4 12B is the candidate ([findings](../spike/findings.md#the-larger-model-for-the-mac)), and whether it fits and how fast it runs on the 16 GB MacBook Air M4 is not yet measured. The phone also needs to find the gateway on the LAN without the user typing an address.

## Decision

### Inference backend

- `INFERENCE_BACKEND=openai-compatible` sends `POST {INFERENCE_URL}/chat/completions` to a local model server. That covers llama.cpp's `llama-server`, Ollama and LM Studio, so the model and runtime can change without a gateway change.
- Every request asks for greedy decoding (`temperature: 0`, `top_k: 1`), `stream: false`, and `max_tokens` from `INFERENCE_MAX_OUTPUT_TOKENS` (default 2048). `top_k` is not part of the OpenAI API, so a server that ignores it may still sample with its own top-k. Check that the server you use honors it.
- `INFERENCE_TIMEOUT_MS` (default 600000, 10 minutes) caps a request. A timeout, a connection error, a non-2xx status, or a response without message content fails the job as `backend_error`, so the phone may retry it.
- Google publishes GGUF builds of Gemma 4 12B on Hugging Face (`google/gemma-4-12B-it-qat-q4_0-gguf`, Apache 2.0). Which build and which server to use is a measurement for the MacBook Air, not a decision made here.

### mDNS

- The gateway advertises `_fieldnote._tcp` with `bonjour-service` 1.4.4. The TXT record holds `v=1` and the first 16 hex characters of the certificate fingerprint, so the phone can show which Mac it found.
- mDNS gives the phone an address, never trust. Trust comes only from the pairing proof and the pinned fingerprint ([ADR 0010](0010-tls-and-pinned-pairing.md)).
- `MDNS=auto` (the default) advertises only when `HOST` is not a loopback address. `on` and `off` override it.

## Consequences

- To use the gateway from the phone, the user starts it with `HOST=0.0.0.0` (or the Mac's LAN address) and a model server. The default stays loopback with no model, so a fresh install exposes nothing.
- The gateway does not start or manage the model server. Its log names the configured backend and model at startup.
