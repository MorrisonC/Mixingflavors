# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: graphics.spec.js >> Graphics QA - Visual Regression >> Gameplay View Snapshot - Desktop
- Location: tests\playwright\graphics.spec.js:111:5

# Error details

```
Error: A snapshot doesn't exist at C:\Development\Mixingflavors\tests\playwright\graphics.spec.js-snapshots\gameplay-view-desktop-chromium-win32.png, writing actual.
```

# Page snapshot

```yaml
- generic [active] [ref=e1]: Your browser does not support the canvas tag.
```

# Test source

```ts
  18  |       }
  19  |     });
  20  | 
  21  |     page.on('pageerror', err => {
  22  |       consoleErrors.push(err.message);
  23  |     });
  24  | 
  25  |     await page.goto('/');
  26  |   });
  27  | 
  28  |   async function callGameAPI(page, args) {
  29  |       await page.evaluate(() => {
  30  |          window.__godot_promise = new Promise(resolve => {
  31  |             window.__godot_resolve = resolve;
  32  |          });
  33  |       });
  34  | 
  35  |       await page.evaluate((a) => { window.gameAPI(a); }, args);
  36  | 
  37  |       const res = await page.evaluate(async () => {
  38  |          return await window.__godot_promise;
  39  |       });
  40  |       return res;
  41  |   }
  42  | 
  43  |   async function waitForEngine(page) {
  44  |     await page.waitForFunction(() => window.gameAPI !== undefined, { timeout: 60000 });
  45  |     await page.waitForTimeout(2000);
  46  |   }
  47  | 
  48  |   async function checkCanvasNotBlank(page) {
  49  |     const isBlank = await page.evaluate(() => {
  50  |         const canvas = document.getElementById('canvas');
  51  |         if (!canvas) return true;
  52  |         const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
  53  |         if (!gl) return true;
  54  | 
  55  |         const pixels = new Uint8Array(4);
  56  |         gl.readPixels(canvas.width/2, canvas.height/2, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
  57  | 
  58  |         if (pixels[3] === 0) return true;
  59  | 
  60  |         const isBlack = pixels[0] === 0 && pixels[1] === 0 && pixels[2] === 0;
  61  |         const isWhite = pixels[0] === 255 && pixels[1] === 255 && pixels[2] === 255;
  62  | 
  63  |         return isBlack || isWhite;
  64  |     });
  65  |     return !isBlank;
  66  |   }
  67  | 
  68  |   const viewports = [
  69  |     { name: 'Mobile', width: 375, height: 812 },
  70  |     { name: 'Desktop', width: 1920, height: 1080 },
  71  |     { name: 'Ultrawide', width: 2560, height: 1080 }
  72  |   ];
  73  | 
  74  |   for (const vp of viewports) {
  75  |     test(`Main Menu Snapshot - ${vp.name}`, async ({ page }) => {
  76  |       await page.setViewportSize({ width: vp.width, height: vp.height });
  77  |       await waitForEngine(page);
  78  |       // Wait for rendering to stabilize
  79  |       await page.waitForTimeout(1000);
  80  |       // Pause engine so canvas is stable
  81  |       await callGameAPI(page, ['pause_engine']);
  82  |       expect(await page.screenshot()).toMatchSnapshot(`main-menu-${vp.name.toLowerCase()}.png`, { maxDiffPixels: 10000 });
  83  |       await callGameAPI(page, ['unpause_engine']);
  84  | 
  85  |       // const isRendered = await checkCanvasNotBlank(page);
  86  |       // expect(isRendered).toBeTruthy(); // Removing this as getting 0 alpha is possible when paused
  87  |       // const isRendered = await checkCanvasNotBlank(page);
  88  |       // expect(isRendered).toBeTruthy(); // Removing this as getting 0 alpha is possible when paused
  89  |       expect(consoleErrors.filter(e => !e.includes('Node not found'))).toHaveLength(0);
  90  |       expect(webGLWarnings.filter(w => !w.includes('GL Driver Message') && !w.includes('OpenGL API OpenGL ES'))).toHaveLength(0);
  91  |     });
  92  | 
  93  |     test(`Level Select Snapshot - ${vp.name}`, async ({ page }) => {
  94  |       await page.setViewportSize({ width: vp.width, height: vp.height });
  95  |       await waitForEngine(page);
  96  |       await callGameAPI(page, ['switch_mode', 1]);
  97  |       await page.waitForTimeout(2000);
  98  | 
  99  |       await callGameAPI(page, ['pause_engine']);
  100 |       expect(await page.screenshot()).toMatchSnapshot(`level-select-${vp.name.toLowerCase()}.png`, { maxDiffPixels: 10000 });
  101 |       await callGameAPI(page, ['unpause_engine']);
  102 | 
  103 |       // const isRendered = await checkCanvasNotBlank(page);
  104 |       // expect(isRendered).toBeTruthy();
  105 |       // const isRendered = await checkCanvasNotBlank(page);
  106 |       // expect(isRendered).toBeTruthy();
  107 |       expect(consoleErrors.filter(e => !e.includes('Node not found'))).toHaveLength(0);
  108 |       expect(webGLWarnings.filter(w => !w.includes('GL Driver Message') && !w.includes('OpenGL API OpenGL ES'))).toHaveLength(0);
  109 |     });
  110 | 
  111 |     test(`Gameplay View Snapshot - ${vp.name}`, async ({ page }) => {
  112 |       await page.setViewportSize({ width: vp.width, height: vp.height });
  113 |       await waitForEngine(page);
  114 |       await callGameAPI(page, ['switch_mode', 2]);
  115 |       await page.waitForTimeout(3000);
  116 | 
  117 |       await callGameAPI(page, ['pause_engine']);
> 118 |       expect(await page.screenshot()).toMatchSnapshot(`gameplay-view-${vp.name.toLowerCase()}.png`, { maxDiffPixels: 10000 });
      |                                       ^ Error: A snapshot doesn't exist at C:\Development\Mixingflavors\tests\playwright\graphics.spec.js-snapshots\gameplay-view-desktop-chromium-win32.png, writing actual.
  119 |       await callGameAPI(page, ['unpause_engine']);
  120 | 
  121 |       // const isRendered = await checkCanvasNotBlank(page);
  122 |       // expect(isRendered).toBeTruthy();
  123 |       expect(consoleErrors.filter(e => !e.includes('Node not found'))).toHaveLength(0);
  124 |       expect(webGLWarnings.filter(w => !w.includes('GL Driver Message') && !w.includes('OpenGL API OpenGL ES'))).toHaveLength(0);
  125 |     });
  126 |   }
  127 | });
  128 | 
```