// Minimal Playwright driver for the LnP UI checks on a VM whose cert is not trusted (ignoreHTTPSErrors).
// Usage: node pw.mjs <script.json>   — script: {"base":"https://host","steps":[{"goto":"/path"},{"shot":"name"},{"click":"text=..."},{"fill":{"sel":"...","value":"..."}},{"wait":"text=..."},{"text":"sel"}]}
import { createRequire } from 'node:module'; import fs from 'node:fs'; import { execSync } from 'node:child_process';
const vars = {}; const sub = v => typeof v === 'string' ? v.replace(/\$\{(\w+)\}/g, (_, k) => vars[k] ?? process.env[k] ?? '') : v;
const require = createRequire(process.env.PW_ROOT + '/node_modules/playwright/package.json');
const { chromium } = require(process.env.PW_ROOT + '/node_modules/playwright');
const script = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')); const out = process.env.PW_OUT || '/tmp/lnp-ui';
const VP = (process.env.PW_VIEWPORT || '1366x900').split('x').map(Number); const vp = h => ({ width: VP[0], height: h || VP[1] });
// PW_HEADED=1: a real Chrome window (tabs, address bar) on $DISPLAY, sized to the viewport — the screen is captured outside
// (x11grab); timestamps then stay on ONE clock (T0E, printed) across contexts. A pointer is drawn in-page and glides to each click.
const HEADED = !!process.env.PW_HEADED;
const browser = await chromium.launch({ headless: !HEADED, executablePath: process.env.PW_CHROME || undefined,
  ...(HEADED ? { args: [`--window-size=${VP[0]},${VP[1]}`, '--window-position=0,0', '--no-first-run', '--no-default-browser-check', '--hide-crash-restore-bubble', '--disable-infobars'], ignoreDefaultArgs: ['--enable-automation'] } : {}) });
const POINTER = `(() => { if (window.top !== window) return; const c = document.createElement('div'); c.id = '__pw_pointer'; c.style.cssText = 'position:fixed;left:-50px;top:-50px;width:22px;height:30px;z-index:2147483647;pointer-events:none;';
  c.innerHTML = '<svg viewBox="0 0 22 30" width="22" height="30"><path d="M2 2 L2 24 L8 18 L12 28 L15 27 L11 17 L19 17 Z" fill="#fff" stroke="#000" stroke-width="1.6" stroke-linejoin="round"/></svg>';
  const add = () => document.documentElement.appendChild(c); document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', add) : add();
  document.addEventListener('mousemove', e => { c.style.left = (e.clientX - 2) + 'px'; c.style.top = (e.clientY - 2) + 'px'; }, true); })();`;
const place = async pg => { if (!HEADED) return; try { const cdp = await pg.context().newCDPSession(pg); const { windowId } = await cdp.send('Browser.getWindowForTarget'); await cdp.send('Browser.setWindowBounds', { windowId, bounds: { left: 0, top: 0, width: VP[0], height: VP[1], windowState: 'normal' } }); await cdp.detach(); } catch (e) { console.log('WIN ' + e.message.slice(0, 80)); } };
const mkctx = async opts => { const c = await browser.newContext({ ignoreHTTPSErrors: true, ...(HEADED ? { viewport: null } : { viewport: vp(opts.height) }), ...opts.state ? { storageState: sub(opts.state) } : {}, ...(!HEADED && process.env.PW_VIDEO ? { recordVideo: { dir: process.env.PW_VIDEO, size: vp(opts.height) } } : {}) }); if (HEADED) await c.addInitScript(POINTER); return c; };
const ctx = await mkctx({});
let ctx2 = ctx; let page = await ctx.newPage(); await place(page); const log = []; let T0 = Date.now(); if (HEADED) console.log('T0E ' + T0);
const glide = async l => { if (!HEADED) return; try { const b = await l.boundingBox(); if (b) await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2, { steps: 14 }); } catch {} };
const netAll = []; const hook = pg => { pg.on('requestfailed', rq => netAll.push(`FAILED ${rq.method()} ${rq.url().slice(0,160)} ${rq.failure()?.errorText}`)); pg.on('response', async r => { const u = r.url(); if (/mdms-v2|\/license\/|\/accounts?\/|\/workflow\//.test(u)) { let n = ''; try { const j = JSON.parse(await r.text()); n = Array.isArray(j) ? `len=${j.length}` : (j.mdms ? `mdms=${j.mdms.length}` : (j.certificateTypes ? `types=${j.certificateTypes.length}` : '')); } catch {} netAll.push(`${r.status()} ${r.request().method()} ${u.slice(0,6000)} ${n}`); } }); pg.on('console', m => { if (m.type() === 'error') log.push('console.error: ' + m.text().slice(0, 200)); }); pg.on('response', async r => { if (r.status() >= 400 && !r.url().includes('favicon')) { let b = ''; if (r.url().includes('/license/')) { try { b = (await r.text()).slice(0, 300); } catch {} } log.push(`HTTP ${r.status()} ${r.request().method()} ${r.url().slice(0, 160)} ${b}`); } }); };
hook(page);
for (const s of script.steps) {
  try {
    if (s.newContext) { await page.context().close().catch(()=>{}); ctx2 = await mkctx(s.newContext); page = await ctx2.newPage(); await place(page); hook(page); if (!HEADED) T0 = Date.now(); }
    if (s.shell) { vars[s.var || 'OUT'] = execSync(sub(s.shell), { encoding: 'utf8', timeout: 120000 }).trim(); console.log(`VAR ${s.var || 'OUT'}=${s.secret ? '<set>' : vars[s.var || 'OUT'].slice(0, 80)}`); }
    if (s.goto) await page.goto(sub(script.base) + sub(s.goto), { waitUntil: 'networkidle', timeout: 60000 });
    if (s.click) { const l = page.locator(sub(s.click)).first(); await glide(l); if (process.env.PW_VIDEO) { await l.evaluate(e => { e.dataset.pwo = e.style.outline; e.style.outline = '3px solid #f0883e'; }).catch(()=>{}); await page.waitForTimeout(500); } await l.click({ timeout: s.timeout || 15000 }); if (process.env.PW_VIDEO) await l.evaluate(e => { e.style.outline = e.dataset.pwo || ''; }).catch(()=>{}); }
    if (s.select) await page.locator(sub(s.select.sel)).first().selectOption(s.select.index !== undefined ? { index: s.select.index } : sub(s.select.value), { timeout: 15000 });
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
    if (s.typeInto) { const l = page.locator(sub(s.typeInto.sel)).first(); await glide(l); await l.click({ timeout: s.timeout || 15000 }); await page.keyboard.type(sub(s.typeInto.value), { delay: 40 }); }
    if (s.js) console.log('JS ' + String(await page.evaluate(sub(s.js))).slice(0, 300));
    if (s.typeKeys) await page.keyboard.type(sub(s.typeKeys), { delay: 40 });
    if (s.setValue) await page.locator(sub(s.setValue.sel)).first().evaluate((el, v) => { const d = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value') || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value'); d.set.call(el, v); el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); }, sub(s.setValue.value));
    if (s.net) { const re = new RegExp(s.net); netAll.filter(l => re.test(l)).forEach(l => console.log('NETALL ' + l)); }
    if (s.upload) await page.locator(s.upload.sel).first().setInputFiles(sub(s.upload.path));
    if (s.saveState) await page.context().storageState({ path: sub(s.saveState) });   // cookies + localStorage → reuse with newContext.state (no second OTP)
    if (s.waitFile) { // {waitFile: path, var: NAME, timeout?: ms, secret?: bool} — poll for a file (no spawn timeout), read digits
      const t0 = Date.now(); let val = ''; console.log(`T wait-start ${((t0 - T0) / 1000).toFixed(1)}`);
      while (Date.now() - t0 < (s.timeout || 420000)) { if (fs.existsSync(s.waitFile) && fs.statSync(s.waitFile).size > 0) { val = fs.readFileSync(s.waitFile, 'utf8').replace(/[^0-9]/g, ''); if (val) break; } await page.waitForTimeout(2000); }
      vars[s.var] = val || 'NONE'; console.log(`T wait-end ${((Date.now() - T0) / 1000).toFixed(1)}`); console.log('VAR ' + s.var + '=' + (s.secret ? '<set>' : vars[s.var]));
    }
    if (s.url) console.log('URL ' + page.url());
    if (s.wheel) { for (let i = 0; i < (s.wheel.steps || 1); i++) { await page.mouse.wheel(0, s.wheel.dy); await page.waitForTimeout(s.wheel.delay || 200); } }   // scroll like a reader
    if (s.beat) console.log(`BEAT ${s.beat} @${((Date.now() - T0) / 1000).toFixed(2)} ${page.url()}`);   // a narration beat starts here (video time of the recorded context)
    if (s.shot) { await page.screenshot({ path: `${out}/${s.shot}.png`, fullPage: !!s.full }); console.log(`SHOT ${s.shot} @${((Date.now() - T0) / 1000).toFixed(2)} ${page.url()}`); }
    console.log('OK ' + JSON.stringify(s).replace(/"value":"[^"]*"/g, '"value":"…"').slice(0, 120));
  } catch (e) { console.log('FAIL ' + JSON.stringify(s).slice(0, 120) + ' :: ' + String(e.message).split('\n')[0].slice(0, 200)); if (s.shot) await page.screenshot({ path: `${out}/${s.shot}-fail.png` }).catch(()=>{}); }
}
console.log('URL ' + page.url()); log.slice(0, 15).forEach(l => console.log('NET ' + l));
await browser.close();
