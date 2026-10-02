// Minimal Playwright driver for the LnP UI checks on a VM whose cert is not trusted (ignoreHTTPSErrors).
// Usage: node pw.mjs <script.json>   — script: {"base":"https://host","steps":[{"goto":"/path"},{"shot":"name"},{"click":"text=..."},{"fill":{"sel":"...","value":"..."}},{"wait":"text=..."},{"text":"sel"}]}
import { createRequire } from 'node:module'; import fs from 'node:fs'; import { execSync } from 'node:child_process';
const vars = {}; const sub = v => typeof v === 'string' ? v.replace(/\$\{(\w+)\}/g, (_, k) => vars[k] ?? process.env[k] ?? '') : v;
const require = createRequire(process.env.PW_ROOT + '/node_modules/playwright/package.json');
const { chromium } = require(process.env.PW_ROOT + '/node_modules/playwright');
const script = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')); const out = process.env.PW_OUT || '/tmp/lnp-ui';
const browser = await chromium.launch({ headless: true, executablePath: process.env.PW_CHROME || undefined });
const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1366, height: 900 } });
let ctx2 = ctx; let page = await ctx.newPage(); const log = [];
const netAll = []; const hook = pg => { pg.on('requestfailed', rq => netAll.push(`FAILED ${rq.method()} ${rq.url().slice(0,160)} ${rq.failure()?.errorText}`)); pg.on('response', async r => { const u = r.url(); if (/mdms-v2|\/license\/|\/accounts?\/|\/workflow\//.test(u)) { let n = ''; try { const j = JSON.parse(await r.text()); n = Array.isArray(j) ? `len=${j.length}` : (j.mdms ? `mdms=${j.mdms.length}` : (j.certificateTypes ? `types=${j.certificateTypes.length}` : '')); } catch {} netAll.push(`${r.status()} ${r.request().method()} ${u.slice(0,6000)} ${n}`); } }); pg.on('console', m => { if (m.type() === 'error') log.push('console.error: ' + m.text().slice(0, 200)); }); pg.on('response', async r => { if (r.status() >= 400 && !r.url().includes('favicon')) { let b = ''; if (r.url().includes('/license/')) { try { b = (await r.text()).slice(0, 300); } catch {} } log.push(`HTTP ${r.status()} ${r.request().method()} ${r.url().slice(0, 160)} ${b}`); } }); };
hook(page);
for (const s of script.steps) {
  try {
    if (s.newContext) { await page.context().close().catch(()=>{}); ctx2 = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1366, height: s.newContext.height || 900 } }); page = await ctx2.newPage(); hook(page); }
    if (s.shell) { vars[s.var || 'OUT'] = execSync(sub(s.shell), { encoding: 'utf8', timeout: 120000 }).trim(); console.log(`VAR ${s.var || 'OUT'}=${s.secret ? '<set>' : vars[s.var || 'OUT'].slice(0, 80)}`); }
    if (s.goto) await page.goto(script.base + sub(s.goto), { waitUntil: 'networkidle', timeout: 60000 });
    if (s.click) await page.locator(sub(s.click)).first().click({ timeout: 15000 });
    if (s.fill) await page.locator(s.fill.sel).first().fill(sub(s.fill.value), { timeout: 15000 });
    if (s.press) await page.keyboard.press(s.press);
    if (s.wait) await page.locator(sub(s.wait)).first().waitFor({ timeout: s.timeout || 30000 });
    if (s.waitUrl) await page.waitForURL(u => u.toString().includes(sub(s.waitUrl)), { timeout: s.timeout || 30000 });
    if (s.sleep) await page.waitForTimeout(s.sleep);
    if (s.text) console.log('TEXT ' + (s.text === 'body' ? await page.innerText('body') : await page.locator(s.text).first().innerText()).replace(/\s+/g, ' ').slice(0, s.max || 600));
    if (s.controls) console.log('CONTROLS ' + JSON.stringify(await page.locator('button, a[href], input[type=submit]').evaluateAll(els => els.map(e => [e.tagName, (e.innerText || e.value || '').trim().slice(0, 40), e.getAttribute('href') || e.getAttribute('name') || ''].join('|')).filter(x => x.split('|')[1]))).slice(0, 900));
    if (s.inputs) console.log('INPUTS ' + JSON.stringify(await page.locator('input, select, textarea').evaluateAll(els => els.filter(e => e.type !== 'hidden').map(e => [e.tagName, e.type, e.name || e.id, e.placeholder || '', e.autocomplete || ''].join('|')))).slice(0, 900));
    if (s.fillFirst !== undefined) await page.locator('input:not([type=hidden]):not([type=submit]):not([type=checkbox])').first().fill(sub(s.fillFirst), { timeout: 15000 });
    if (s.fillDigits !== undefined) { const code = sub(s.fillDigits); const boxes = page.locator('input[type=text]:not([type=hidden]), input[inputmode=numeric]'); const n = await boxes.count(); if (n >= code.length) { for (let i = 0; i < code.length; i++) { await boxes.nth(i).click(); await page.keyboard.type(code[i]); } } else { await boxes.first().click(); await page.keyboard.type(code, { delay: 60 }); } }
    if (s.typeInto) { const l = page.locator(sub(s.typeInto.sel)).first(); await l.click({ timeout: 15000 }); await page.keyboard.type(sub(s.typeInto.value), { delay: 40 }); }
    if (s.js) console.log('JS ' + String(await page.evaluate(sub(s.js))).slice(0, 300));
    if (s.typeKeys) await page.keyboard.type(sub(s.typeKeys), { delay: 40 });
    if (s.setValue) await page.locator(sub(s.setValue.sel)).first().evaluate((el, v) => { const d = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value') || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value'); d.set.call(el, v); el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); }, sub(s.setValue.value));
    if (s.net) { const re = new RegExp(s.net); netAll.filter(l => re.test(l)).forEach(l => console.log('NETALL ' + l)); }
    if (s.upload) await page.locator(s.upload.sel).first().setInputFiles(s.upload.path);
    if (s.url) console.log('URL ' + page.url());
    if (s.shot) { await page.screenshot({ path: `${out}/${s.shot}.png`, fullPage: !!s.full }); console.log('SHOT ' + s.shot); }
    console.log('OK ' + JSON.stringify(s).replace(/"value":"[^"]*"/g, '"value":"…"').slice(0, 120));
  } catch (e) { console.log('FAIL ' + JSON.stringify(s).slice(0, 120) + ' :: ' + String(e.message).split('\n')[0].slice(0, 200)); if (s.shot) await page.screenshot({ path: `${out}/${s.shot}-fail.png` }).catch(()=>{}); }
}
console.log('URL ' + page.url()); log.slice(0, 15).forEach(l => console.log('NET ' + l));
await browser.close();
