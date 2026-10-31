/** Runs the model on the Mac. Returns the model's raw text answer. */
export interface InferenceBackend {
  readonly name: string;
  generate(prompt: string): Promise<string>;
}
