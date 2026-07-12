# Groq backend for Spartan

Groq's API is OpenAI-compatible, so a Groq backend is `GrokProvider` with a
different `base_url` + key. Three small, additive edits to Gene's Spartan; no
existing behaviour changes.

## 1. Add `GroqProvider` to `spartan.py`

Paste directly after the `GrokProvider` class (it reuses Grok's OpenAI-compatible
call path, only swapping the endpoint + key — no OpenAI-only params like
`prompt_cache_retention`, which Groq rejects):

```python
class GroqProvider(GrokProvider):
    """Groq (OpenAI-compatible, fast Llama/Mixtral inference)."""
    def __init__(self, backend_config=None):
        bc = backend_config or {}
        api_key = os.getenv("GROQ_API_KEY")
        if not api_key:
            raise ValueError("GROQ_API_KEY environment variable not set.")
        self.model = bc.get("model", "llama-3.3-70b-versatile")
        self.max_output_tokens = bc.get("max_output_tokens", 8192)
        self.client = openai_lib.OpenAI(
            api_key=api_key,
            base_url="https://api.groq.com/openai/v1",
        )
        gui_print(f"GroqProvider initialized: {self.model}", "system")
```

(If `GrokProvider.__init__` sets other attributes your call path reads, mirror
them here. The point is: same OpenAI-compatible `client.chat.completions.create`
path, Groq endpoint.)

## 2. Register it in the provider dispatch

In the `get_provider`/provider-selection block (where `elif provider == "grok":`
lives), add:

```python
    elif provider == "groq":
        return GroqProvider(bc)
```

## 3. Add the backend to `spartan_config.yaml`

```yaml
  #AVAILABLE (Groq — fast OpenAI-compatible Llama inference)
  groq_llama:
    provider: groq
    available: true
    requires_env: "GROQ_API_KEY"
    model: "llama-3.3-70b-versatile"
    mode: external
    max_output_tokens: 8192
```

Then set `active_backend: groq_llama` (or switch at runtime via the entity's
backend-switch tool).

## Env

```
export GROQ_API_KEY=...
```

Verified: a live `chat.completions.create` against
`https://api.groq.com/openai/v1` with `llama-3.3-70b-versatile` through the
`openai` Python client returns normally — the exact path `GroqProvider` uses.
