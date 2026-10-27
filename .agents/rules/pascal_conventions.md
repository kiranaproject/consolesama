# Object Pascal Coding Conventions & Architectural Standards

All Pascal source files and test suites in `consolesama` follow strict Object Pascal coding conventions shared across the Kirana/Floria ecosystem.

---

## 1. Compiler Directives & Dialect

Every unit begins with:

```pascal
unit ConsoleSama.<Subsystem>.<Role>;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords} // When advanced record methods or static class functions are needed
```

- **Dialect**: `{$mode objfpc}` (Free Pascal object-oriented Pascal mode).
- **Strings**: `{$H+}` enables long `AnsiString` by default.
- **Advanced Records**: `{$modeswitch advancedrecords}` enables methods and constructors on `record` types.

---

## 2. Mandatory Empty Parentheses `()` on Zero-Parameter Routines

Every zero-parameter `procedure`, `function`, `constructor`, or `destructor` declaration and call site **must** include empty parentheses `()`:

```pascal
// Declarations
procedure Invalidate(); virtual;
function GetCols(): Integer;
constructor Create();
destructor Destroy(); override;

// Call sites
View.Repaint();
inherited Destroy();
Screen.Free();
```

---

## 3. Formatting & Block Alignment

- **Indentation**: Exactly 2 spaces per indentation level. Never use tabs.
- **`begin..end` Alignment**: The opening `begin` keyword must appear on a new line, aligned directly beneath the statement controlling it.
- **Comments**: Always use `//` for single-line comments. Never use nested `{}` block comments.
- **Memory Safety**: Always wrap resource allocations in `try..finally Free()` blocks.

---

## 4. Unit Filenames & Namespace Declarations

- Unit filenames are strictly lowercase and dot-separated: `consolesama.<subsystem>.pas`.
- The unit header declaration is strictly PascalCase: `unit ConsoleSama.<Subsystem>;`.
