---
description: Design Rules and Guidelines (Material Symbols Usage)
---

# Design Rules

This skill defines the design guidelines for the **Dot Pixel Art Maker** application.
Follow these rules strictly when implementing UI components or designing screens.

## 1. Iconography (Material Symbols)

This application uses **Material Symbols Rounded** as the primary icon set.

### 1.1 Dependency

Ensure the `material_symbols_icons` package is included in `pubspec.yaml`:

```yaml
dependencies:
  material_symbols_icons: ^4.2906.0
```

### 1.2 Usage in Code

- **DO use**: `Symbols.<icon_name>` class from `package:material_symbols_icons/symbols.dart`.
- **DO NOT use**: `CupertinoIcons` (strictly prohibited) or standard `Icons` (avoid where possible).

**Example:**

```dart
import 'package:material_symbols_icons/symbols.dart';

// Correct
Icon(Symbols.home)
Icon(Symbols.settings)

// Incorrect
Icon(CupertinoIcons.home)
Icon(Icons.home)
```

### 1.3 Usage in Design (.pen files)

- Use `icon_font` type nodes.
- Set `iconFontFamily` to `"Material Symbols Rounded"`.
- Set `iconFontName` to the icon name (snake_case).

**Example:**

```javascript
// Correct
myIcon = I(parent, {
  type: "icon_font",
  iconFontName: "photo_camera", // snake_case name
  iconFontFamily: "Material Symbols Rounded",
  width: 24,
  height: 24,
  fill: "#000000",
});
```

## 2. Color Palette

- **Primary Text**: `#000000` or `#1C1B1F`
- **Secondary Text**: `#757575`
- **Background**: `#FFFFFF` or `#FAFAFA`
- **Accent Color**: Use specific colors defined in the design (e.g. `#2196F3` for active states).

## 3. Typography

- In `.pen` files, always use the `fill` property to set text color.
- Default font family: `Inter` or system default.
- Font Weights: `bold`, `medium`, `regular`.

## 4. Layout

- Base screen width for design: **360px**.
- Use 8pt grid system for spacing (8, 16, 24, 32...).
- Use `fill_container` for expanding widgets.
