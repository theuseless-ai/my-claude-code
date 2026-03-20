---
name: frontend-ui-ux
description: "Design-first UI development. Accessibility-first component architecture, responsive design patterns, and design system integration."
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
---

# Frontend UI/UX — Design-First Development

## Design-First Methodology

1. **Understand requirements** — What problem does this UI solve?
2. **Component inventory** — What existing components can be reused?
3. **Layout structure** — Semantic HTML skeleton first, styling second
4. **Accessibility** — WCAG 2.1 AA compliance from the start, not retrofitted
5. **Responsive design** — Mobile-first, progressive enhancement

## Component Architecture (Atomic Design)

| Level | Examples | Responsibility |
|---|---|---|
| Atoms | Button, Input, Label, Icon | Single-purpose, no business logic |
| Molecules | SearchBar, FormField, Card | Combine atoms, minimal logic |
| Organisms | Header, ProductList, LoginForm | Business logic, data fetching |
| Templates | PageLayout, DashboardLayout | Structure, no content |
| Pages | HomePage, SettingsPage | Content + data binding |

## Accessibility Checklist

- [ ] Semantic HTML elements (`<nav>`, `<main>`, `<article>`, not `<div>` soup)
- [ ] All images have meaningful `alt` text (or `alt=""` for decorative)
- [ ] Interactive elements are keyboard-accessible (Tab, Enter, Escape)
- [ ] Color contrast ratio ≥ 4.5:1 for normal text, ≥ 3:1 for large text
- [ ] Form inputs have associated `<label>` elements
- [ ] ARIA attributes only when semantic HTML is insufficient
- [ ] Focus management for modals and dynamic content
- [ ] Screen reader testing with descriptive landmarks

## Responsive Breakpoints

```css
/* Mobile first */
.component { /* base mobile styles */ }

@media (min-width: 640px) { /* sm: tablet */ }
@media (min-width: 768px) { /* md: small laptop */ }
@media (min-width: 1024px) { /* lg: desktop */ }
@media (min-width: 1280px) { /* xl: large desktop */ }
```

## CSS Methodology

- Follow the project's existing convention (Tailwind, CSS Modules, styled-components, BEM)
- Avoid `!important` — fix specificity instead
- Use CSS custom properties for design tokens (colors, spacing, typography)
- Prefer `gap` over margin hacks for spacing
- Use `clamp()` for fluid typography: `font-size: clamp(1rem, 2.5vw, 2rem)`

## Animation Standards

- Use `transform` and `opacity` for performant animations (GPU-composited)
- Respect `prefers-reduced-motion` media query
- Keep durations under 300ms for UI feedback, 500ms for transitions
- Use `ease-out` for enters, `ease-in` for exits
