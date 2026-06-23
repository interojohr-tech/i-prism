-- ================================================================
-- 로컬스토리지 → MySQL 마이그레이션 가이드
-- app.js의 state 객체를 DB에 INSERT하는 순서와 방법
-- ================================================================

-- ----------------------------------------------------------------
-- 마이그레이션 순서 (외래키 의존성 고려)
-- ----------------------------------------------------------------
-- 1. org_nodes          (조직도 — 부모 노드 먼저)
-- 2. users              (사용자 — evaluator1/2 자기참조: 두 번 삽입)
-- 3. eval_templates     (템플릿)
-- 4. template_items     (템플릿 항목)
-- 5. goal_cycles        (목표 사이클)
-- 6. goals              (목표)
-- 7. eval_cycles        (평가 사이클)
-- 8. cycle_users        (사이클 사용자 스냅샷)
-- 9. evaluations        (평가 레코드)
-- 10. eval_reviews      (평가 상세)
-- 11. eval_achievements (업적 항목)
-- 12. upward_assignments
-- 13. peer_assignments
-- 14. relative_groups
-- 15. result_submissions
-- 16. cycle_template_assignments
-- 17. role_weights / evaluator_weights / grade_thresholds / distribution_matrix
-- 18. system_settings

-- ----------------------------------------------------------------
-- 사용자 자기참조 해결 방법
-- ----------------------------------------------------------------
-- 1단계: evaluator1_id, evaluator2_id 없이 INSERT
INSERT INTO users (id, employee_no, name, email, role, title, division, team, active)
SELECT ...;

-- 2단계: 평가자 FK 업데이트
UPDATE users SET evaluator1_id = :ev1, evaluator2_id = :ev2 WHERE id = :id;

-- ----------------------------------------------------------------
-- JSON 필드 → 정규화 테이블 변환 예시
-- ----------------------------------------------------------------

-- app.js state.cycles[].evaluations 구조:
-- {
--   "userId": {
--     "self":   { performance: {score, grade, items:[], achievements:[]}, competency:..., attitude:... },
--     "first":  { ... },
--     "second": { ... },
--     "final":  { ... },
--     "status": { self:"submitted", first:"completed", ... },
--     "adjustment": { grade, gradeManual, feedback, reason, adjustedAt },
--     "orgAdjustment": { grade, gradeManual, reason, submittedBy, submittedAt },
--     "published": false,
--     "reportFeedback": { resultConfirmed, opinion, interviewRequested, hrStatus, ... }
--   }
-- }

-- evaluations 테이블 INSERT 예시:
INSERT INTO evaluations (
  cycle_id, user_id,
  status_self, status_first, status_second, status_final,
  adj_grade, adj_grade_manual, adj_feedback, adj_reason, adj_adjusted_at,
  org_adj_grade, org_adj_grade_manual, org_adj_reason, org_adj_submitted_by, org_adj_submitted_at,
  published,
  result_confirmed, confirmed_at, opinion, opinion_submitted, opinion_at,
  interview_requested, hr_status, hr_confirmed, hr_memo
) VALUES (
  'cycle_001', 'user_001',
  'submitted', 'completed', 'completed', 'pending',
  'B', 0, NULL, NULL, NULL,
  'B', 0, NULL, NULL, NULL,
  0,
  0, NULL, NULL, 0, NULL,
  0, NULL, 0, NULL
);

-- eval_reviews 테이블 INSERT 예시 (자기평가 - 역량):
INSERT INTO eval_reviews (evaluation_id, review_type, category, score, grade, comment, item_scores, overall_feedback)
VALUES (
  LAST_INSERT_ID(), 'self', 'competency',
  85.5, 'A', '자기평가 의견',
  '{"item_01": 4, "item_02": 5, "item_03": 3}',
  '전반적으로 역량 향상에 노력했습니다.'
);

-- eval_achievements INSERT 예시:
INSERT INTO eval_achievements (evaluation_id, review_type, sort_order, name, goal, detail, weight, score, grade)
VALUES
  (1, 'self', 0, '신제품 출시 프로젝트 관리', '프로젝트 일정 준수율 95%', '실제 달성 95.3%', 50, 90, 'A'),
  (1, 'self', 1, '고객 만족도 향상',          'CS 점수 85점 이상',       '실제 87점 달성',   50, 85, 'A');

-- ----------------------------------------------------------------
-- upward_assignments 변환 예시
-- app.js: cycle.upwardAssignments = [ { id, evaluatorId, targetId, source, status, answer:{...} } ]
-- ----------------------------------------------------------------
INSERT INTO upward_assignments (id, cycle_id, evaluator_id, target_id, source, status, score, grade, comment, item_scores, submitted_at)
VALUES
  ('ua_001', 'cycle_001', 'user_010', 'user_003', 'organization', 'completed',
   82.0, 'A', '리더십이 훌륭합니다',
   '{"item_01":4,"item_02":5}',
   '2025-04-15 14:30:00');

-- ----------------------------------------------------------------
-- relative_groups 변환 예시
-- app.js: cycle.relativeGroups = { userId: { overrideGroup, overrideReason, locked } }
-- ----------------------------------------------------------------
INSERT INTO relative_groups (cycle_id, user_id, override_group, override_reason, locked)
VALUES
  ('cycle_001', 'user_010', '김본부장', '조직개편으로 팀 이동', 1),
  ('cycle_001', 'user_011', '이본부장', NULL, 0);

-- ----------------------------------------------------------------
-- 사이클 날짜 기간 변환 예시
-- app.js: cycle.periods = { self: {start, end}, first: {start, end}, ... }
-- ----------------------------------------------------------------
INSERT INTO eval_cycles (
  id, name, status,
  self_start, self_end,
  first_start, first_end,
  second_start, second_end,
  upward_start, upward_end,
  peer_start, peer_end,
  grade_start, grade_end,
  feedback_start, feedback_end,
  use_upward, use_peer, peer_count
) VALUES (
  'cycle_2025_h1', '2025년 상반기 인사평가', 'done',
  '2025-03-01', '2025-03-15',
  '2025-03-16', '2025-03-31',
  '2025-04-01', '2025-04-15',
  '2025-03-01', '2025-03-15',
  '2025-03-01', '2025-03-15',
  '2025-04-16', '2025-04-30',
  '2025-05-01', '2025-05-15',
  1, 1, 3
);

-- ================================================================
-- 유용한 검증 쿼리
-- ================================================================

-- 외래키 제약 검증 (사이클-사용자 일치 확인)
SELECT e.cycle_id, e.user_id
FROM evaluations e
LEFT JOIN cycle_users cu ON cu.cycle_id = e.cycle_id AND cu.user_id = e.user_id
WHERE cu.id IS NULL;

-- 평가 진행률 전체 요약
SELECT
  c.id, c.name, c.status,
  COUNT(DISTINCT e.user_id)                                              AS total_users,
  SUM(CASE WHEN e.status_self   = 'submitted'  THEN 1 ELSE 0 END)       AS self_done,
  SUM(CASE WHEN e.status_first  = 'completed'  THEN 1 ELSE 0 END)       AS first_done,
  SUM(CASE WHEN e.status_second = 'completed'  THEN 1 ELSE 0 END)       AS second_done,
  SUM(CASE WHEN e.published     = 1            THEN 1 ELSE 0 END)       AS published,
  SUM(CASE WHEN e.result_confirmed = 1         THEN 1 ELSE 0 END)       AS confirmed
FROM eval_cycles c
LEFT JOIN evaluations e ON e.cycle_id = c.id
GROUP BY c.id
ORDER BY c.created_at DESC;

-- 등급 배분율 (사이클별)
SELECT
  c.name AS cycle_name,
  COALESCE(e.org_adj_grade, e.adj_grade) AS grade,
  COUNT(*) AS cnt,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY c.id), 1) AS pct
FROM eval_cycles c
JOIN evaluations e ON e.cycle_id = c.id
WHERE (e.org_adj_grade IS NOT NULL OR e.adj_grade IS NOT NULL)
GROUP BY c.id, grade
ORDER BY c.name, grade;
