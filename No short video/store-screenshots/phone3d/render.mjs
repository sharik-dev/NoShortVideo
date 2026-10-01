// node render.mjs out.png "shot=build/x.png&yaw=-20&pitch=5&w=1000&h=1600"
import { chromium } from '/Users/sharikmohamed/Documents/tools/shotsmith/node_modules/playwright-core/index.mjs';
const [, , ...jobs] = process.argv;
const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
for (let i = 0; i < jobs.length; i += 2) {
  const out = jobs[i], qs = jobs[i + 1];
  const p = new URLSearchParams(qs); const w = +(p.get('w') || 1000), h = +(p.get('h') || 1600);
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  page.on('pageerror', e => console.error('pageerror', e.message));
  await page.goto(`http://localhost:8765/index.html?${qs}`);
  await page.waitForFunction('window.__done === true', null, { timeout: 60000 });
  await page.locator('canvas').screenshot({ path: out, omitBackground: true });
  console.log(out, JSON.stringify(await page.evaluate('window.__info')));
  await page.close();
}
await browser.close();
