# MD Reader — sample document

A quick tour of all the formatting this reader handles. The sidebar on the left
shows the table of contents; the progress bar in the toolbar tracks how far
you've scrolled.

## 1. Inline formatting

You can write **bold**, *italic*, ***bold italic***, ~~strikethrough~~, and
`inline code`. Links work too: [Anthropic](https://www.anthropic.com).

## 2. Lists

### 2.1 Bulleted

- First item with some longer text that will wrap across more than one line so
  you can see how the line spacing looks in practice.
- Second item
  - Nested item
  - Another nested item
- Third item

### 2.2 Numbered

1. Plan the work
2. Do the work
3. Ship the work

### 2.3 Tasks

- [x] Set up project
- [x] Build sidebar
- [ ] Add live reload
- [ ] Ship to App Store

## 3. Blockquotes

> The best code is no code at all.
>
> — Jeff Atwood

## 4. Code

Inline `let x = 42` works. Fenced blocks render like this:

```swift
struct ContentView: View {
    var body: some View {
        Text("Hello, MD Reader")
            .font(.title)
            .padding()
    }
}
```

```python
def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
```

## 5. Tables

| Time      | Stake             | Outcome                              |
|-----------|-------------------|--------------------------------------|
| Q3 2026   | Enrichment Engine | Pays for itself (filters, search)    |
| Q4 2026   | + MCP Gateway     | Activates when agent traffic scales  |
| 2027      | + Discovery layer | Insurance for non-MCP agents         |

## 6. Long section

Here is a longer block of prose so the progress indicator has somewhere to go.
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor
incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in
culpa qui officia deserunt mollit anim id est laborum.

### 6.1 Subsection

More text here. The sidebar should let you jump straight to this subsection,
and the highlight should move as you scroll past it.

### 6.2 Another subsection

And another one, so the outline has some shape.

## 7. Horizontal rule

---

Everything above the rule belongs to the document body. Below it, you can keep
adding sections and the ToC will keep tracking them.

## 8. Last section

You made it to the end. The progress indicator should show 100%.
