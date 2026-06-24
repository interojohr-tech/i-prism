const express = require("express");
const path = require("path");
const fs = require("fs");

const app = express();
const PORT = process.env.PORT || 3000;

// ── Supabase 설정 (환경변수로 주입) ─────────────────────────────────────────
const SUPABASE_URL   = process.env.SUPABASE_URL;   // https://xxxx.supabase.co
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
app.use(express.json({ limit: "100mb" }));
app.use(express.static(path.join(__dirname), { index: false }));

// ── 루트: 초기 상태 HTML에 주입 ─────────────────────────────────────────────
app.get("/", async (req, res) => {
  try {
    const stateData = await dbGet();
    const stateJson = stateData ? JSON.stringify(stateData) : "null";
    let html = fs.readFileSync(path.join(__dirname, "index.html"), "utf-8");
    const openaiKey = process.env.OPENAI_API_KEY || "";
    html = html.replace(
      "</head>",
      `<script>window.__INITIAL_STATE__ = ${stateJson}; window.__OPENAI_API_KEY__ = ${JSON.stringify(openaiKey)};</script>\n</head>`
    );
    res.send(html);
  } catch (e) {
    console.error("상태 로드 오류:", e);
    res.sendFile(path.join(__dirname, "index.html"));
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
