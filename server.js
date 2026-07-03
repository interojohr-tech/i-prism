const express = require("express");
const path = require("path");
const fs = require("fs");
const helmet = require("helmet");

const app = express();
const PORT = process.env.PORT || 3000;

// ── OpenAI 설정 (서버에만 보관 — 클라이언트로 절대 내려보내지 않음) ──────────────
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || "";
const OPENAI_ALLOWED_MODELS = ["gpt-4o-mini"];
const OPENAI_MAX_TOKENS_CAP = 4000;

// ── Supabase 설정 (환경변수로 주입) ─────────────────────────────────────────
const SUPABASE_URL   = (process.env.SUPABASE_URL || "").replace(/\/rest\/v1\/?$/, "").replace(/\/$/, "") || undefined;   // https://xxxx.supabase.co
const SUPABASE_KEY   = process.env.SUPABASE_KEY;   // anon public key
const TABLE          = "app_state";
const STATE_KEY      = "main";

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.warn("⚠ SUPABASE_URL / SUPABASE_KEY 환경변수가 없습니다. 로컬 파일 모드로 동작합니다.");
}

// ── 로컬 fallback 파일 경로 (로컬 개발용) ───────────────────────────────────
const LOCAL_FILE = path.join(__dirname, "database", "state.json");

// ── Supabase REST 헬퍼 ───────────────────────────────────────────────────────
async function dbGet() {
  if (!SUPABASE_URL) return readLocalFile();
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/${TABLE}?key=eq.${STATE_KEY}&select=value`,
    { headers: supaHeaders() }
  );
  const rows = await res.json();
  return rows?.[0]?.value ?? null;
}

async function dbSet(data) {
  if (!SUPABASE_URL) return writeLocalFile(data);
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${TABLE}`, {
    method: "POST",
    headers: { ...supaHeaders(), "Prefer": "resolution=merge-duplicates" },
    body: JSON.stringify({ key: STATE_KEY, value: data }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Supabase 저장 실패 [${res.status}]: ${body}`);
  }
  console.log("Supabase 저장 성공");
}

function supaHeaders() {
  return {
    "apikey": SUPABASE_KEY,
    "Authorization": `Bearer ${SUPABASE_KEY}`,
    "Content-Type": "application/json",
  };
}

// ── 로컬 파일 fallback (Supabase 없을 때) ───────────────────────────────────
function readLocalFile() {
  try {
    if (!fs.existsSync(LOCAL_FILE)) return null;
    return JSON.parse(fs.readFileSync(LOCAL_FILE, "utf-8"));
  } catch { return null; }
}

function writeLocalFile(data) {
  const dir = path.dirname(LOCAL_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const tmp = LOCAL_FILE + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(data));
  fs.renameSync(tmp, LOCAL_FILE);
}

// ── 미들웨어 ─────────────────────────────────────────────────────────────────
// CSP: 이 앱은 인라인 onclick 핸들러·인라인 style을 화면 전반에서 사용하므로
// script-src/style-src에 'unsafe-inline'이 불가피하다(전면 리팩터 없이는 제거 불가).
// 대신 나머지 지시어(object-src, frame-ancestors 등)는 엄격하게 잠가 클릭재킹·플러그인 삽입 등은 막는다.
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'", "https://cdn.sheetjs.com", "https://cdn.jsdelivr.net"],
      scriptSrcAttr: ["'unsafe-inline'"], // 화면 전반의 onclick="..." 인라인 핸들러가 동작하려면 필요
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", "data:", "blob:"],
      connectSrc: ["'self'"],
      objectSrc: ["'none'"],
      baseUri: ["'self'"],
      frameAncestors: ["'none'"],
    },
  },
}));
app.use(express.json({ limit: "100mb" }));
app.use(express.static(path.join(__dirname), { index: false }));

// ── 루트: 초기 상태 HTML에 주입 ─────────────────────────────────────────────
app.get("/", async (req, res) => {
  try {
    const stateData = await dbGet();
    const stateJson = stateData ? JSON.stringify(stateData) : "null";
    let html = fs.readFileSync(path.join(__dirname, "index.html"), "utf-8");
    html = html.replace(
      "</head>",
      `<script>window.__INITIAL_STATE__ = ${stateJson};</script>\n</head>`
    );
    res.send(html);
  } catch (e) {
    console.error("상태 로드 오류:", e);
    res.sendFile(path.join(__dirname, "index.html"));
  }
});

// ── API: OpenAI 채팅 완성 프록시 (키를 서버에만 보관, 클라이언트로 전달하지 않음) ──
app.post("/api/ai/chat", async (req, res) => {
  if (!OPENAI_API_KEY) {
    return res.status(500).json({ error: { message: "서버에 OPENAI_API_KEY가 설정되어 있지 않습니다." } });
  }
  const { model, messages, response_format, temperature, max_tokens } = req.body || {};
  if (!OPENAI_ALLOWED_MODELS.includes(model)) {
    return res.status(400).json({ error: { message: `허용되지 않은 model입니다: ${model}` } });
  }
  if (!Array.isArray(messages) || !messages.length) {
    return res.status(400).json({ error: { message: "messages가 필요합니다." } });
  }
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 60000);
    const upstream = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${OPENAI_API_KEY}`,
      },
      signal: controller.signal,
      body: JSON.stringify({
        model,
        messages,
        ...(response_format ? { response_format } : {}),
        temperature: typeof temperature === "number" ? temperature : 0.5,
        max_tokens: Math.min(Number(max_tokens) || 1000, OPENAI_MAX_TOKENS_CAP),
      }),
    });
    clearTimeout(timeout);
    const data = await upstream.json();
    res.status(upstream.status).json(data);
  } catch (e) {
    console.error("OpenAI 프록시 오류:", e);
    res.status(502).json({ error: { message: e.name === "AbortError" ? "OpenAI 응답 시간이 초과되었습니다." : e.message } });
  }
});

// ── API: 상태 조회 ───────────────────────────────────────────────────────────
app.get("/api/state", async (req, res) => {
  try {
    const data = await dbGet();
    res.json(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── API: 상태 저장 ───────────────────────────────────────────────────────────
app.post("/api/state", async (req, res) => {
  try {
    await dbSet(req.body);
    res.json({ ok: true });
  } catch (e) {
    console.error("저장 오류:", e);
    res.status(500).json({ ok: false, error: e.message });
  }
});

// ── 서버 시작 ────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`I-PRISM 서버 실행 중 → http://localhost:${PORT}`);
  console.log(SUPABASE_URL ? `Supabase 연결: ${SUPABASE_URL}` : "로컬 파일 모드");
});
