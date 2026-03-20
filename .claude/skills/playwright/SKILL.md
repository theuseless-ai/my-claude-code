---
name: playwright
description: "Browser automation and E2E testing with Playwright. Navigate pages, fill forms, click elements, capture screenshots, and write end-to-end tests."
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# Playwright Browser Automation

## Setup

Ensure Playwright is installed:
```bash
npx playwright install
```

## Common Operations

### Navigate and Screenshot
```typescript
import { chromium } from 'playwright';
const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto('https://example.com');
await page.screenshot({ path: 'screenshot.png' });
await browser.close();
```

### Form Interaction
```typescript
await page.fill('input[name="email"]', 'user@example.com');
await page.fill('input[name="password"]', 'password');
await page.click('button[type="submit"]');
await page.waitForNavigation();
```

### E2E Test Pattern
```typescript
import { test, expect } from '@playwright/test';

test('user can login', async ({ page }) => {
  await page.goto('/login');
  await page.fill('[data-testid="email"]', 'user@test.com');
  await page.fill('[data-testid="password"]', 'pass');
  await page.click('[data-testid="submit"]');
  await expect(page).toHaveURL('/dashboard');
});
```

### Wait Strategies
- `page.waitForSelector('.element')` — wait for DOM element
- `page.waitForNavigation()` — wait for page navigation
- `page.waitForResponse(url)` — wait for network response
- `page.waitForLoadState('networkidle')` — wait for network quiet

## Running Tests
```bash
npx playwright test                    # run all tests
npx playwright test --headed           # with browser visible
npx playwright test --project=chromium # specific browser
npx playwright show-report             # view HTML report
```
