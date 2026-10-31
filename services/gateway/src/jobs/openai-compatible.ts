import type { InferenceBackend } from "./backend.js";

export interface OpenAiCompatibleOptions {
  /** Base URL that ends in /v1, for example http://127.0.0.1:8080/v1 (llama.cpp server). */
  baseUrl: string;
  model: string;
  timeoutMs: number;
  maxOutputTokens: number;
}

interface ChatCompletion {
  choices?: { message?: { content?: unknown } }[];
}

/**
 * Calls a local server that speaks the OpenAI chat completions API, such as
 * llama.cpp's `llama-server`, Ollama or LM Studio, with greedy decoding so a
 * rerun of the same prompt gives the same answer (ADR 0008).
 */
export class OpenAiCompatibleBackend implements InferenceBackend {
  readonly name = "openai-compatible";

  constructor(private readonly options: OpenAiCompatibleOptions) {}

  async generate(prompt: string): Promise<string> {
    const url = `${this.options.baseUrl.replace(/\/+$/, "")}/chat/completions`;
    let response: Response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          model: this.options.model,
          messages: [{ role: "user", content: prompt }],
          temperature: 0,
          top_k: 1,
          max_tokens: this.options.maxOutputTokens,
          stream: false,
        }),
        signal: AbortSignal.timeout(this.options.timeoutMs),
      });
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      throw new Error(`model server request failed: ${reason}`, { cause: error });
    }
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 200);
      throw new Error(`model server answered ${String(response.status)}: ${detail}`);
    }
    const body = (await response.json()) as ChatCompletion;
    const content = body.choices?.[0]?.message?.content;
    if (typeof content !== "string")
      throw new Error("model server response has no message content");
    return content;
  }
}
