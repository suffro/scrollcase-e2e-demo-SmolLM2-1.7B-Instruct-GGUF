# Build a local LLM into a Scrollcase box

A **large language model** is the kind of model behind a chat assistant: you give it text, it
continues it. Normally you reach one through somebody's API — an account, a key, a network round
trip, and a bill.

This demo takes **SmolLM2-1.7B-Instruct**, a small instruction-tuned language model quantised to
4 bits in GGUF form, and ships it as a signed, self-contained box.

> **Before you start.** This workshop downloads the model **twice** — once to record what it is,
> once to put it in the box — at **1.06 GB each time**, so about **2.1 GB** in total. Inside a
> Codespace that is a couple of minutes. Generation runs on 2 vCPUs, so expect an answer to take
> tens of seconds, not the instant reply you get from a hosted chat service.

<big> **Follow these steps to create, sign, build, verify and run the box:** </big>

## 1. Install Scrollcase CLI

```sh
npm install -g scrollcase
```

## 2. Initialize Scrollcase project

`init` creates the workspace, then asks one question:

```sh
scrollcase init --no-example
```

| It asks | Answer |
| --- | --- |
| This project needs pixi and conda-pack to build a box.<br>Install them into …/.scrollcase/toolchain? [Y/n] | `Y` (just press Enter) |

---

That is the only prompt here. `--no-example` skips the disposable sample box — you are packaging a
real model instead — and the questions about the Node, Python and Rust consumer templates come with
that sample, so they do not appear either.

> Both tools land **inside the project**, under `.scrollcase/toolchain/`. Nothing is installed
> system-wide and nothing is added to `PATH`; deleting that directory undoes it.
>
> If the `pixi` download fails, run the command again — the checksum is verified before anything is
> installed, so a failed download leaves nothing half-written.

## 3. Create the scroll

The **scroll** is the box's declarative input: identity, target, the model to fetch, and what the
box must be able to do. You do not write it by hand — you build it up with commands.

### 3a. The skeleton

```sh
scrollcase new scroll --python-version 3.11 --min-ram-gb 4
```

It asks you a short set of questions — use ↑/↓ and Enter on the menus:

| It asks | Answer |
| --- | --- |
| Which **target**? | `linux-x86_64-cpu` |
| **Box ID** | `llm-demo` |
| **Upstream revision** | `2d4a76a30b4af41ecd395c35725ac11688d4cfe4` |
| **Asset base URL** | `https://assets.example.org/boxes` |
| Which **weights mode**? | `embed` |
| Which **execution kind**? | `python-script` |
| Which **script source**? | `existing project script` |
| **Script path** | `entrypoint.py` |

---

That is the whole list, and every one of them is something nothing else could answer: what this box
is for, what it is called, which version of the model is inside, where you will publish it, and what
runs when someone starts it. The model and runtime identity, the box version, the pixi version and
the interpreter path are all filled in for you.

The two flags:

- `--python-version 3.11` — the newer default would otherwise be used, and this model's llama.cpp
  stack was tested on 3.11 for this demo. It has to be set at creation time because it goes into
  `pixi.toml` as well as the scroll.
- `--min-ram-gb 4` — a real measured constraint, not a guess. The weights occupy ~1.0 GB and the
  attention cache adds 384 MB at the 2048-token context `entrypoint.py` asks for, which lands around
  1.5–1.8 GB resident. 4 GB is that with room to breathe, and it is now a fact a consumer can check
  *before* unpacking a gigabyte.

You now have `scrolls/llm-demo/linux-x86_64-cpu/` with three files: `scroll.json`, its `pixi.toml`,
and a starter `self_test.py`.

Nothing to adjust: `entrypoint.py` does not hard-code where the model lives. It reads the box's own
`box.json` at run time and follows the `modelCacheSubdir` declared there, so the default is fine and
the application keeps working if it ever changes. (If you do need to change a field, that is
`scrollcase edit scroll` — run it with no flags and it lists what you can set.)

### 3b. The model

`add asset` **downloads the file once** and records the size and SHA-256 it actually found. Those
two values are the reason a scroll used to be painful to write: nobody can know them without
fetching the file. **This one is 1.06 GB, so give it a few minutes.**

```sh
HF=https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/2d4a76a30b4af41ecd395c35725ac11688d4cfe4

scrollcase add asset llm-demo $HF/smollm2-1.7b-instruct-q4_k_m.gguf
```

**One command, where the sentiment demo needs three.** A GGUF is a single container holding the
weights, the tokenizer *and* the chat template, so there is no separate `tokenizer.json` or
`config.json` to fetch and keep in step with it. That is a real property of the format, and it is
why the box below has exactly one asset.

The URL is pinned to one immutable commit, and from now on the recorded hash is checked on every
build — a replaced file upstream fails the build instead of quietly changing the box.

### 3c. The files that ship with it

```sh
scrollcase add file llm-demo MODEL_NOTICE.md \
  --to THIRD_PARTY_NOTICES/smollm2/MODEL_NOTICE.md

scrollcase add file llm-demo APACHE-2.0.txt \
  --to THIRD_PARTY_NOTICES/smollm2/APACHE-2.0.txt
```

`entrypoint.py` is already in the scroll — `--script` put it there.

### 3d. The dependency

```sh
scrollcase add dep llm-demo llama-cpp-python --version ">=0.3.30,<0.4"
```

One line, and it is worth looking at what it drags in. `llama-cpp-python` is a binding, so the
compiled `llama.cpp` arrives with it — and so do `fastapi`, `uvicorn`, `pydantic-settings`,
`numpy`, `diskcache` and several more, because the upstream package also ships an OpenAI-compatible
server this box never starts. You will see every one of them by name in the licence inventory in
step 4. That is the point of the inventory: *one* declared dependency is not the same as one
dependency shipped, and the box tells you which it is instead of letting you assume.

The exact versions are pinned by `pixi.lock` in the next step, not by this range.

### 3e. The environment and the self-test

```sh
scrollcase add env llm-demo PYTHONDONTWRITEBYTECODE=1
```

**One variable, and it earns its place — read this bit.** The sentiment demo declares three
`*_OFFLINE` variables because its stack contains real Hugging Face downloaders that would otherwise
reach for a hub. This stack has no such client: `entrypoint.py` imports `llama_cpp` and nothing
else, and what keeps the box offline is that there is no code in it that phones home. Copying
`HF_HUB_OFFLINE=1` across would look reassuring and guarantee nothing — so it is not here. A
declaration in this project is supposed to mean something.

`PYTHONDONTWRITEBYTECODE=1` does mean something, in two places:

- **At build time.** The self-test runs with the payload directory as its working directory, and the
  payload digest is computed *after* it. Without this variable, `import entrypoint` in the self-test
  leaves a `__pycache__/entrypoint.cpython-311.pyc` behind, and that file — which embeds a build
  timestamp — is then hashed into the signed payload and shipped inside the box.
- **At run time.** `verify --extracted` re-hashes the whole tree against the signed digest. A box
  unpacked once and kept, then run, would write that same `__pycache__` into a payload that had
  already been verified, and would fail to verify a second time.

And the box must be able to import what it was built for. This name is signed into the release, so
anyone receiving the box can re-check it:

```sh
scrollcase add import llm-demo llama_cpp
scrollcase remove import llm-demo json
```

The last line drops the placeholder that `scrollcase new scroll` started you with.

Now open `scrolls/llm-demo/linux-x86_64-cpu/self_test.py` — the one file here that is yours to
write, because it is the check that decides whether this box is worth signing — and replace it with:

```python
"""Self-test: the box must load the model and answer a known question, or it is not signed."""

import os
import sys

sys.path.insert(0, os.getcwd())

from entrypoint import generate

answer, statistics = generate("What is the capital of France?")

assert answer.strip(), "the model produced no output"
assert "paris" in answer.lower(), f"unexpected answer: {answer!r}"
assert statistics["output_tokens"] > 0, "no tokens were generated"

print("self-test ok")
```

This is the check that matters: it loads a gigabyte of weights with the box's own interpreter and
makes the real model answer, so a box that cannot generate is never signed.

> **Why this asserts a substring and not a sentence.** `entrypoint.py` decodes greedily, so the same
> build on the same machine produces the same answer every time — but that answer is a sentence, and
> a thread count or a llama.cpp point release can reword it without anything being wrong. Asserting
> `"paris" in answer.lower()` tests what the box is for. Asserting the exact sentence would build a
> guard that eventually fails for a reason nobody cares about, and teaches whoever meets it to
> delete the guard.

> **Look at what you did not write.** No `pythonEntryPoint` — the target admits only one. No file
> size, no hash, no `selfTest.files` list: the `add` commands recorded all of it. The only file you
> opened in an editor is `self_test.py`, which is real Python rather than a string with escaped
> newlines — and it is the one thing here that is genuinely a decision.
>
> Packaging the same model for Linux, macOS and Windows does not mean doing this three times. Put
> what they share in `scrolls/llm-demo/scroll.json` and give each target a short file that declares
> `"extends": "../scroll.json"` plus its own differences — see
> [one box, several targets](https://scrollcase.dev/reference/scroll#one-box-several-targets).

---

### This flow without interactions

Here you can check this same flow but with all the declerations passed explicitly with CLI flags, instead of answering any setup questions in the terminal. This is needed for CI or enviornments where you can't interact with the terminal, or if you just want to explicitly declare all the settings.

<details>
<summary><b>Here you have this same flow but with explicit declarations only</b></summary>

<br>

```sh
scrollcase new scroll \
  --target linux-x86_64-cpu \
  --box-id llm-demo \
  --source-revision 2d4a76a30b4af41ecd395c35725ac11688d4cfe4 \
  --asset-base-url https://assets.example.org/boxes \
  --weights embed \
  --execution python-script --script entrypoint.py \
  --python-version 3.11 \
  --min-ram-gb 4

HF=https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/2d4a76a30b4af41ecd395c35725ac11688d4cfe4
scrollcase add asset llm-demo $HF/smollm2-1.7b-instruct-q4_k_m.gguf

scrollcase add file llm-demo MODEL_NOTICE.md \
  --to THIRD_PARTY_NOTICES/smollm2/MODEL_NOTICE.md
scrollcase add file llm-demo APACHE-2.0.txt \
  --to THIRD_PARTY_NOTICES/smollm2/APACHE-2.0.txt

scrollcase add dep llm-demo llama-cpp-python --version ">=0.3.30,<0.4"

scrollcase add env llm-demo PYTHONDONTWRITEBYTECODE=1

scrollcase add import llm-demo llama_cpp
scrollcase remove import llm-demo json
```

The other flags — `--model-id`, `--runtime-id`, `--version`, `--pixi-version` and the remaining
`compatibility` ones — exist too, and are left out here on purpose: each has a default worth
taking. `scrollcase help` lists them all.

`self_test.py` is still yours to write — see 3e.

</details>

## 4. Lock and audit

`lock` pins the exact packages; `audit` writes the licence inventory the build will re-check.

```sh
scrollcase lock llm-demo/linux-x86_64-cpu

scrollcase audit llm-demo/linux-x86_64-cpu --write
```

Open the inventory it writes. This is where the one line you added in 3d turns into the real list.

## 5. Git commit

Scrollcase refuses to build from a dirty Git working tree, so save what you just wrote in a local
commit first:

```sh
git add . && git commit -m "Package SmolLM2-1.7B-Instruct"
```

This Codespace has no remote, so the commit stays here and cannot change the demo repository.

## 6. Sign and build

`keygen` creates your signing key pair: every box is signed, and the public half is what anyone
who receives the box uses to check it. `build` then installs the locked environment, fetches the
model, checks its hash against what the scroll pins, packs it all, runs the self-test, and signs
the result.

> **This step is the slow one.** The model is downloaded again here — `add asset` fetched it to find
> out what it was; `build` fetches it to put it in the box, and checks it against the hash recorded
> then. There is no cache between the two on purpose: the build starts from a clean scratch tree
> every time, which is part of what makes rebuilding the same commit produce a byte-identical box.
> On top of that, the self-test in step 3e is a real generation, so the build spends time actually
> running the model before it will sign it.

```sh
scrollcase keygen

scrollcase build llm-demo/linux-x86_64-cpu
```

> The 1.06 GB of weights are **stored, not compressed**, in the archive — there is nothing to gain
> by deflating an already-quantised tensor file, and trying costs minutes. The finished archive is
> roughly the weights plus a compressed Python environment.

## 7. Verify

```sh
scrollcase verify .scrollcase/dist/boxes/llm-demo/1.0.0/linux-x86_64-cpu/*.release.json --self-test
```

## ✓ That's it

Now you have a self-contained and signed box with its own deterministic and portable Python environment, that can be delivered as a complete, target-specific, verifiable product artifact that can run on another machine without the need for the end user to assemble that environment and manage its dependencies.

### And in this case, that means something extra

The box you just built answers questions **with no network connection, no API key and no account** —
the model is inside it, and the machine it runs on is the only machine involved. Nothing you type
into it leaves the box.

## How to run the box

There are 3 ways to run a Scrollcase box. Your prompt goes after `--` — and if you leave it out
entirely, the box opens a [chat](#chat-with-it) instead:

### a. Scrollcase CLI

```sh
scrollcase run .scrollcase/dist/boxes/llm-demo/1.0.0/linux-x86_64-cpu/*.release.json \
  -- What is the capital of France?
```

Try something it has to compose rather than recall:

```sh
scrollcase run .scrollcase/dist/boxes/llm-demo/1.0.0/linux-x86_64-cpu/*.release.json \
  -- Explain what a hash function is, in two sentences.
```

The answer goes to stdout and the timings go to stderr, so you can pipe one without the other:

```sh
scrollcase run .scrollcase/dist/boxes/llm-demo/1.0.0/linux-x86_64-cpu/*.release.json \
  -- Name three primary colours. > answer.txt
```

### b. Scrollcase consumers <small> (Node, Python or Rust) </small>

`init` also creates quick **Node, Python, and Rust** examples under `consumer-templates/`. Point one
at the built release and pass the prompt as the box's arguments to run it from an application.

### c. Your custom implementation

<br>

---

## Chat with it

Run the box with **no arguments at all** — no `--`, nothing after it:

```sh
scrollcase run .scrollcase/dist/boxes/llm-demo/1.0.0/linux-x86_64-cpu/*.release.json
```

```text
loading smollm2-1.7b-instruct-q4_k_m.gguf …
ready in 1.4s · 2 threads · 2048-token context
/exit or Ctrl-D to quit, Ctrl-C to cancel an answer
> what is a hash function?
generating …
A hash function maps data of any size to a fixed-size value. …
41 tokens in 6.8s · 6.0 tok/s
> give me an example of one
```

<sub>Shape of a session, not a recording — the timings depend on the machine, and the model's
wording is its own.</sub>

That second question has no subject in it. It works because the box keeps the conversation and
sends it back each turn — which is the whole difference between a chat and a loop that calls a
one-shot twice.

**Nothing was rebuilt for this.** Same release file, same signature, same `entrypoint.py`. The mode
is decided by whether there are arguments: words are a question, nothing is a conversation. There is
no second box and no `--chat` flag, because a flag would have had to be declared in the scroll, and
a box that behaves differently depending on how it is invoked is a worse thing to hand someone than
one that reads its own argument list.

The part you feel immediately is the load. A one-shot run pays ~1–2 s of model loading for every
question; a chat pays it once and every turn after that is generation only. On a 2-vCPU Codespace
that is the difference between the box feeling like a program and feeling like a conversation.

**What the keys do:**

| | |
| --- | --- |
| `/exit` or **Ctrl-D** | end the session — exit code 0 |
| **Ctrl-C** *while it is answering* | abandon that answer and go back to the prompt |
| **Ctrl-C** *at the prompt* | clear the line; it does **not** quit |

A cancelled answer is dropped along with the question that asked for it, so the history stays a
clean alternation and the next answer is not conditioned on a question the model never finished.

> **The context fills up, and the box says so.** Everything in the conversation is re-sent every
> turn, against a 2048-token window shared with the answer. When it no longer fits, the oldest
> exchanges are dropped — oldest first, because a follow-up refers to what was just said — and you
> get a `(dropped 2 older message(s) to fit the context)` line on stderr. The system prompt is never
> dropped, and neither is the question you just asked. It is a small model with a small window; the
> honest thing is to show you when it starts forgetting rather than to fail on the sixth turn.

The answer appears all at once rather than word by word, after a `generating …` line — this is CPU
inference, so expect tens of seconds for a long answer.

And the same split as before still holds: **only answers go to stdout.** The `>` prompt, the
timings and the notices are all stderr, so this works and gives you a file of nothing but answers:

```sh
printf 'name three primary colours\nnow name three secondary ones\n' \
  | scrollcase run .scrollcase/dist/boxes/llm-demo/1.0.0/linux-x86_64-cpu/*.release.json \
  > answers.txt
```

> **The self-test did not become interactive.** It still calls `generate()` and still asks one
> question, because what it has to prove at build time is that a gigabyte of weights loads and
> answers — not that a terminal loop reads lines. A test that needed a TTY would be a test that
> could not run in CI.

---

### About the model

SmolLM2-1.7B-Instruct, quantised to 4 bits. It is a **demonstration**, and it is a **small** model:
it states false things fluently and gives you no signal that it is doing so. Do not use it for
factual lookup, for decisions about people, or for anything you would not check yourself — see
[`MODEL_NOTICE.md`](MODEL_NOTICE.md).

---

### Docs quick-links:

[Overview](https://scrollcase.dev/getting-started/overview) ·
[Quickstart](https://scrollcase.dev/getting-started/quickstart) ·
[CLI reference](https://scrollcase.dev/reference/cli) ·
[Consumer APIs](https://scrollcase.dev/reference/api)
