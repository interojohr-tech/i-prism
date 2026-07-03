# I-PRISM (Interojo Performance Review & Improvement System)

인터로조 인사평가 시스템. 자기평가 → 1차/2차 평가 → 상향/동료평가 → 종합평가(본부장) →
최종 승인(사장/회장) → 결과 공개까지 전체 평가 사이클을 관리한다.

## 현재 아키텍처 (중요)

- **프론트엔드**: 프레임워크·빌드 도구 없는 순수 vanilla JS SPA. `app.js` 하나가 화면 렌더링과
  모든 사용자 액션(저장·제출·조정 등)을 담당한다. 화면 전반이 인라인 `onclick`/`style` 속성에
  의존하므로, 클래스/모듈 기반으로 리팩터링하지 않는 한 CSP의 `script-src`/`style-src`에
  `unsafe-inline`이 불가피하다(`server.js`의 helmet 설정 참고).
- **서버**: `server.js`는 Express 정적 파일 서버 + `/api/ai/chat` OpenAI 프록시 역할만 한다.
  OpenAI API 키는 서버 환경변수(`OPENAI_API_KEY`)에만 보관하며 클라이언트로 내려가지 않는다.
- **데이터 저장 — 실제로는 브라우저 `localStorage`만 사용한다.** `server.js`에는 Supabase
  REST API를 호출하는 `/api/state` 조회·저장 라우트와 로컬 파일(`database/state.json`) 폴백
  코드가 존재하지만, **현재 `app.js`는 이 API를 전혀 호출하지 않는다.** 즉 `SUPABASE_URL`/
  `SUPABASE_KEY` 환경변수를 설정해도 실제 평가 데이터 저장에는 영향이 없고, 모든 상태는 각
  사용자의 브라우저 `localStorage`(키: `company-review-system-v2`)에만 존재한다. 브라우저
  데이터를 지우거나 다른 기기/브라우저로 접속하면 그 사용자가 보는 데이터가 달라진다.
- **`database/*.sql`(schema.sql, migration_guide.sql, queries.sql)는 실제로 연결되어 있지
  않은 "향후 이전 설계 문서"**다. 심지어 `schema.sql`은 MySQL 문법으로 작성되어 있어, `server.js`가
  호출하려는 Supabase(Postgres 기반 REST API)와도 서로 다른 설계다. 현재 소스오브트루스는 위에서
  설명한 localStorage이며, 이 SQL 파일들을 실제 스키마로 오해하지 않도록 주의한다.
- 서버 기반 실 DB 이전과 그에 따른 보안 강화(인증, 암호화 등)는 **의도적으로 이후 단계**로
  미뤄둔 상태다. 기능이 모두 완성된 뒤 정보전략팀 및 외부 보안 전문가와 함께 진행할 예정이며,
  그 전까지는 로그인 세션(`sessionStorage`)과 클라이언트 측 역할 검사만으로 접근을 구분한다.
  즉 지금 단계의 "권한 분리"는 서버가 강제하는 것이 아니라 클라이언트 로직 수준이다.

## 파일 구조

```
├── index.html          # 진입점 — <script>로 app.js 등을 로드
├── app.js              # 전체 로직(렌더링 + 액션 핸들러). 파일 맨 위 주석에 코드 색인(TOC) 있음
├── imported-data.js     # 조직/구성원 시드 데이터 (window.HR_IMPORTED_DATA)
├── styles.css           # 전체 스타일
├── server.js            # Express 정적 서버 + OpenAI 프록시(/api/ai/chat)
├── package.json          # express, helmet 의존성
└── database/             # 향후 Supabase 이전을 위한 설계 문서 (현재 미연결, 위 설명 참고)
```

## 로컬에서 실행하기

`index.html`을 브라우저에서 직접 열어서는 안 된다(OpenAI 프록시가 동작하지 않고, `file://`
환경에서 일부 기능이 깨진다). 반드시 아래처럼 Node 서버를 통해 실행한다.

```bash
npm install
OPENAI_API_KEY=sk-...  npm start   # PowerShell: $env:OPENAI_API_KEY="sk-..."; npm start
```

기본 포트는 `3000`(환경변수 `PORT`로 변경 가능)이며, 브라우저에서 `http://localhost:3000`으로
접속한다. `OPENAI_API_KEY`가 없어도 서버는 뜨지만, AI 피드백/AI 채점 기능만 비활성화된다.

## 배포

Render에 Node 웹 서비스로 배포되어 있다(`npm start`). 배포 시 최소한 `OPENAI_API_KEY` 환경변수를
설정해야 AI 기능이 동작한다. `SUPABASE_URL`/`SUPABASE_KEY`는 현재 클라이언트가 사용하지 않으므로
설정 여부가 실제 서비스 동작에 영향을 주지 않는다(위 아키텍처 설명 참고).

## 주요 기능 개요

- **평가 입력**: 자기평가, 1차/2차 평가, 상향평가, 동료평가 (개인별/문항별 일괄 입력 모드 지원,
  입력 중 자동 저장)
- **종합평가(본부장)**: 팀별 표준화 점수 기반 추천 등급 + 등급 배분율 가이드 대비 현황, 팀 인원이
  2명 이하라 표준화가 불가능한 인원은 별도 처리
- **조정 세션(인사총무팀)** → **최종 승인(사장/회장)** → **결과 공개**
- **AI 피드백**: 서버 프록시를 통한 자동 성장 피드백 생성, 관리자가 사전 등록한 참고자료 카탈로그
  중에서만 추천 자료를 선택하도록 제한(할루시네이션 방지)
- **감사 로그**: 사이클 상태 변경, 상대평가 확정 취소, 결과 다운로드 등급 조정 이력 외 주요 작업
  이력 (관리자 전용 "감사 로그" 화면)
- **관리자 화면**: 조직 관리, 평가 템플릿, 평가권한(1·2차/상향/동료 배정), 공지사항, 참고자료
  관리, 목표 관리 등

## 코드 찾아보기

`app.js` 파일 맨 위에 각 기능이 대략 몇 번째 줄 근처에 있는지 안내하는 주석 색인이 있다. 정확한
위치는 거기 적힌 함수/섹션 이름을 에디터에서 검색해서 찾는 것을 권장한다(파일이 계속 수정되며
줄 번호가 조금씩 밀릴 수 있음).
