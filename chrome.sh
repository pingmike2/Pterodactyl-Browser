const fs = require("fs");
const os = require("os");
const path = require("path");
const { chromium } = require("playwright");

/* ================= CONFIG ================= */

const TARGET_URL =
  process.env.TARGET_URL ||
  "https://dash.vertos.in/register?ref=6kIlCvyZ";

const MAX_RETRY = parseInt(process.env.MAX_RETRY || "2", 10);

const EXT_BUSTER = path.resolve(__dirname, "extensions/buster/unpacked");
const SCREEN_DIR = path.resolve(__dirname, "screenshots");

/* ================= UTILS ================= */

function ensureDir() {
  if (!fs.existsSync(SCREEN_DIR)) {
    fs.mkdirSync(SCREEN_DIR, { recursive: true });
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function snap(page, name) {
  try {
    const file = path.join(SCREEN_DIR, `${Date.now()}_${name}.png`);
    await page.screenshot({ path: file, fullPage: true });
    console.log("📸", file);
  } catch {}
}

/* ================= EXT ================= */

async function waitExtensionLoaded(context) {
  for (let i = 0; i < 60; i++) {
    if (context.serviceWorkers().length || context.backgroundPages().length) {
      console.log("✅ Buster 已加载");
      return true;
    }
    await sleep(500);
  }
  return false;
}

/* ================= 账号 ================= */

function randomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function genAccount() {
  const firstNames = [
    "Lucas","Ethan","Noah","Liam","Mason",
    "Oliver","James","Benjamin","Elijah","Alexander"
  ];

  const lastNames = [
    "Smith","Johnson","Brown","Taylor","Anderson",
    "Thomas","Jackson","White","Harris","Martin"
  ];

  const first = randomItem(firstNames);
  const last = randomItem(lastNames);

  const num = Math.floor(Math.random() * 900 + 100);

  // ⭐ 用户名（纯字母+数字）
  const usernameStyles = [
    `${first}${last}`,          // LucasSmith
    `${first}${last}${num}`,    // LucasSmith123
    `${first}${num}`,           // Lucas123
    `${first[0]}${last}${num}`  // LSmith123
  ];

  const username = randomItem(usernameStyles);

  // ⭐ 邮箱可以更随意（允许 .）
  const emailStyles = [
    `${first}.${last}${num}`,
    `${first}${last}${num}`,
    `${first[0]}${last}${num}`
  ];

  const emailName = randomItem(emailStyles).toLowerCase();

  return {
    name: username, // ⭐ 修复点：不再有空格
    email: `${emailName}@gmail.com`,
    password: `Aa!${first}${num}${Math.random().toString(36).slice(2,6)}`
  };
}

/* ================= CAPTCHA ================= */

async function clickCheckbox(page) {
  const iframe = await page.waitForSelector(
    'iframe[src*="anchor"]',
    { timeout: 120000 }
  );

  const frame = await iframe.contentFrame();
  const box = await frame.waitForSelector("#recaptcha-anchor");

  await box.click({ force: true });
  await page.waitForTimeout(2000);
}

async function waitChallenge(page) {
  try {
    const iframe = await page.waitForSelector(
      'iframe[src*="bframe"]',
      { timeout: 10000 }
    );
    return await iframe.contentFrame();
  } catch {
    return null; // ⭐ 没 challenge = 已通过
  }
}

/* ⭐ 核心：对称点击 */
async function clickBuster(page, frame) {
  const reload = frame.locator("#recaptcha-reload-button");
  const audio = frame.locator("#recaptcha-audio-button");

  await reload.waitFor();
  await audio.waitFor();

  const r = await reload.boundingBox();
  const a = await audio.boundingBox();

  if (!r || !a) throw new Error("❌ 坐标失败");

  const dx = a.x - r.x;
  const dy = a.y - r.y;

  const x = a.x + dx;
  const y = a.y + dy;

  console.log("📍 solver:", Math.round(x), Math.round(y));

  await page.mouse.click(x, y);
  await page.waitForTimeout(5000);
}

/* ================= 状态 ================= */

async function waitSolved(page, timeout = 180000) {
  const start = Date.now();

  while (Date.now() - start < timeout) {
    // token
    for (const f of page.frames()) {
      try {
        const token = await f.evaluate(() => {
          return document.querySelector(
            "textarea[name='g-recaptcha-response']"
          )?.value;
        });

        if (token && token.length > 30) {
          console.log("✅ token OK");
          return true;
        }
      } catch {}
    }

    // checkbox
    const anchor = page
      .frames()
      .find((f) => f.url().includes("anchor"));

    if (anchor) {
      const checked = await anchor.evaluate(() => {
        return (
          document
            .querySelector("#recaptcha-anchor")
            ?.getAttribute("aria-checked") === "true"
        );
      });

      if (checked) {
        console.log("✅ checkbox OK");
        return true;
      }
    }

    await page.waitForTimeout(2000);
  }

  throw new Error("❌ 验证码超时");
}

/* ================= MAIN ================= */

async function registerOnce() {
  ensureDir();

  let context;
  let page;

  const profile = fs.mkdtempSync(path.join(os.tmpdir(), "pw-"));

  try {
    context = await chromium.launchPersistentContext(profile, {
      headless: false,
      args: [
        `--disable-extensions-except=${EXT_BUSTER}`,
        `--load-extension=${EXT_BUSTER}`,
        "--no-sandbox",
      ],
    });

    if (!(await waitExtensionLoaded(context))) {
      throw new Error("❌ Buster 未加载");
    }

    page = await context.newPage();

    const acc = genAccount();
    console.log("🧾", acc);

    await page.goto(TARGET_URL, { waitUntil: "networkidle" });

    /* ===== 填表 ===== */

    await page.fill('input[name="name"]', acc.name);
    await page.fill('input[name="email"]', acc.email);
    await page.fill('input[name="password"]', acc.password);
    await page.fill(
      'input[name="password_confirmation"]',
      acc.password
    );

    /* ⭐ 修复：点击 label 而不是 input */
    await page.click('label[for="terms"]', { force: true });

    console.log("☑️ 表单完成");
    await snap(page, "form_done");

    /* ===== CAPTCHA ===== */

    await clickCheckbox(page);
    await snap(page, "checkbox");

    const frame = await waitChallenge(page);

    if (frame) {
      console.log("🤖 使用 Buster");
      await clickBuster(page, frame);
    } else {
      console.log("✅ 无 challenge（直接通过）");
    }

    await waitSolved(page);
    await snap(page, "captcha_ok");

    /* ⭐ 修复：用 submit 而不是 click */
    console.log("🚀 提交表单");

    await page.evaluate(() => {
      document.querySelector("form").submit();
    });

    await page.waitForTimeout(8000);
    await snap(page, "done");

    console.log("🎉 成功");

    return { ok: true };
  } catch (e) {
    console.log("💥", e.message);

    if (page) await snap(page, "error");

    return { ok: false };
  } finally {
    if (context) await context.close();
  }
}

/* ================= ENTRY ================= */

(async () => {
  for (let i = 1; i <= MAX_RETRY; i++) {
    console.log(`\n🔄 尝试 ${i}`);

    const r = await registerOnce();

    if (r.ok) process.exit(0);

    await sleep(4000);
  }

  process.exit(1);
})();
