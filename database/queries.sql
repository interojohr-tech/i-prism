-- ================================================================
-- 인터로조 인사평가 시스템 — 주요 쿼리 모음
-- ================================================================

USE interojo_hr;

-- ================================================================
-- [사용자 관리]
-- ================================================================

-- 전체 활성 사용자 조회 (조직도 포함)
SELECT
  u.id, u.employee_no, u.name, u.email, u.role, u.title,
  u.division, u.team, u.active,
  ev1.name AS evaluator1_name,
  ev2.name AS evaluator2_name,
  n.name   AS org_node_name
FROM users u
LEFT JOIN users    ev1 ON ev1.id = u.evaluator1_id
LEFT JOIN users    ev2 ON ev2.id = u.evaluator2_id
LEFT JOIN org_nodes n  ON n.id  = u.org_node_id
WHERE u.active = 1
ORDER BY u.division, u.team, u.name;

-- 사용자 단건 조회
SELECT u.*, ev1.name AS evaluator1_name, ev2.name AS evaluator2_name
FROM users u
LEFT JOIN users ev1 ON ev1.id = u.evaluator1_id
LEFT JOIN users ev2 ON ev2.id = u.evaluator2_id
WHERE u.id = :userId;

-- 사용자 등록
INSERT INTO users (id, employee_no, name, email, role, title, division, team, org_node_id, active)
VALUES (:id, :employeeNo, :name, :email, :role, :title, :division, :team, :orgNodeId, 1);

-- 사용자 정보 수정
UPDATE users
SET employee_no   = :employeeNo,
    name          = :name,
    email         = :email,
    role          = :role,
    title         = :title,
    division      = :division,
    team          = :team,
    org_node_id   = :orgNodeId,
    evaluator1_id = :evaluator1Id,
    evaluator2_id = :evaluator2Id,
    active        = :active
WHERE id = :userId;

-- 사용자 비활성화
UPDATE users SET active = 0 WHERE id = :userId;

-- 역할별 사용자 목록
SELECT id, name, title, division, team FROM users
WHERE role = :role AND active = 1
ORDER BY division, team, name;

-- ================================================================
-- [조직도]
-- ================================================================

-- 전체 조직도 트리
SELECT id, name, parent_id, node_type, sort_order
FROM org_nodes
ORDER BY sort_order, name;

-- 조직도 노드 등록
INSERT INTO org_nodes (id, name, parent_id, node_type, sort_order)
VALUES (:id, :name, :parentId, :nodeType, :sortOrder);

-- 조직도 노드 삭제
DELETE FROM org_nodes WHERE id = :nodeId;

-- ================================================================
-- [평가 사이클]
-- ================================================================

-- 전체 사이클 목록
SELECT id, name, status,
       self_start, self_end,
       first_start, first_end,
       second_start, second_end,
       grade_start, grade_end,
       results_visible, use_upward, use_peer,
       feedback_mgmt_unlocked,
       created_at
FROM eval_cycles
ORDER BY created_at DESC;

-- 진행중 사이클
SELECT * FROM eval_cycles WHERE status = 'active' LIMIT 1;

-- 사이클 등록
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
  :id, :name, 'paused',
  :selfStart, :selfEnd,
  :firstStart, :firstEnd,
  :secondStart, :secondEnd,
  :upwardStart, :upwardEnd,
  :peerStart, :peerEnd,
  :gradeStart, :gradeEnd,
  :feedbackStart, :feedbackEnd,
  :useUpward, :usePeer, :peerCount
);

-- 사이클 시작 (기존 진행중 → 중지)
UPDATE eval_cycles SET status = 'paused' WHERE status = 'active';
UPDATE eval_cycles SET status = 'active'  WHERE id = :cycleId;

-- 사이클 상태 변경
UPDATE eval_cycles SET status = :status WHERE id = :cycleId;

-- 결과 공개 토글
UPDATE eval_cycles SET results_visible = :visible WHERE id = :cycleId;

-- 피드백 관리 탭 잠금 해제
UPDATE eval_cycles SET feedback_mgmt_unlocked = 1 WHERE id = :cycleId;

-- ================================================================
-- [사이클 사용자 스냅샷]
-- ================================================================

-- 스냅샷 등록 (사이클 시작 시 현재 사용자 정보 복사)
INSERT INTO cycle_users (cycle_id, user_id, employee_no, name, role, title, division, team, org_node_id, evaluator1_id, evaluator2_id, active)
SELECT :cycleId, id, employee_no, name, role, title, division, team, org_node_id, evaluator1_id, evaluator2_id, active
FROM users
WHERE active = 1;

-- 특정 사이클의 피평가 대상자 조회
SELECT * FROM cycle_users
WHERE cycle_id = :cycleId
  AND active   = 1
  AND role NOT IN ('admin')
ORDER BY division, team, name;

-- ================================================================
-- [평가]
-- ================================================================

-- 사이클의 전체 평가 목록 (사용자 정보 포함)
SELECT
  e.*,
  cu.name, cu.role, cu.title, cu.division, cu.team,
  cu.evaluator1_id, cu.evaluator2_id
FROM evaluations e
JOIN cycle_users cu ON cu.cycle_id = e.cycle_id AND cu.user_id = e.user_id
WHERE e.cycle_id = :cycleId
ORDER BY cu.division, cu.team, cu.name;

-- 특정 사용자의 평가 단건
SELECT e.*
FROM evaluations e
WHERE e.cycle_id = :cycleId AND e.user_id = :userId;

-- 평가 레코드 생성 (사이클 시작 시 피평가자 전원 생성)
INSERT IGNORE INTO evaluations (cycle_id, user_id)
SELECT :cycleId, user_id
FROM cycle_users
WHERE cycle_id = :cycleId AND active = 1 AND role NOT IN ('admin');

-- 자기평가 상태 변경
UPDATE evaluations
SET status_self = :status
WHERE cycle_id = :cycleId AND user_id = :userId;

-- 1차 평가 상태 변경
UPDATE evaluations
SET status_first = :status
WHERE cycle_id = :cycleId AND user_id = :userId;

-- 2차 평가 상태 변경
UPDATE evaluations
SET status_second = :status
WHERE cycle_id = :cycleId AND user_id = :userId;

-- 1·2차 조정 등급 저장
UPDATE evaluations
SET adj_grade        = :grade,
    adj_grade_manual = :manual,
    adj_feedback     = :feedback,
    adj_reason       = :reason,
    adj_adjusted_at  = NOW()
WHERE cycle_id = :cycleId AND user_id = :userId;

-- 종합평가(본부장) 등급 저장
UPDATE evaluations
SET org_adj_grade        = :grade,
    org_adj_grade_manual = :manual,
    org_adj_reason       = :reason,
    org_adj_submitted_by = :submittedBy,
    org_adj_submitted_at = NOW()
WHERE cycle_id = :cycleId AND user_id = :userId;

-- 결과 공개
UPDATE evaluations SET published = 1
WHERE cycle_id = :cycleId AND user_id IN (:userIds);

-- 피평가자 결과 확인
UPDATE evaluations
SET result_confirmed = 1, confirmed_at = NOW()
WHERE cycle_id = :cycleId AND user_id = :userId;

-- 피평가자 의견 제출
UPDATE evaluations
SET opinion = :opinion, opinion_submitted = 1, opinion_at = NOW()
WHERE cycle_id = :cycleId AND user_id = :userId;

-- 면담 신청
UPDATE evaluations
SET interview_requested = 1, interview_at = NOW()
WHERE cycle_id = :cycleId AND user_id = :userId;

-- HR 피드백 처리
UPDATE evaluations
SET hr_status     = :status,
    hr_confirmed  = :confirmed,
    hr_memo       = :memo,
    hr_updated_at = NOW()
WHERE cycle_id = :cycleId AND user_id = :userId;

-- ================================================================
-- [평가 리뷰 상세]
-- ================================================================

-- 특정 평가의 전체 리뷰 조회
SELECT * FROM eval_reviews
WHERE evaluation_id = :evaluationId
ORDER BY review_type, category;

-- 리뷰 항목 저장 (UPSERT)
INSERT INTO eval_reviews (evaluation_id, review_type, category, score, grade, comment, item_scores, overall_feedback)
VALUES (:evalId, :reviewType, :category, :score, :grade, :comment, :itemScores, :overallFeedback)
ON DUPLICATE KEY UPDATE
  score            = VALUES(score),
  grade            = VALUES(grade),
  comment          = VALUES(comment),
  item_scores      = VALUES(item_scores),
  overall_feedback = VALUES(overall_feedback);

-- ================================================================
-- [업적 항목]
-- ================================================================

-- 특정 평가·리뷰 유형의 업적 조회
SELECT * FROM eval_achievements
WHERE evaluation_id = :evalId AND review_type = :reviewType
ORDER BY sort_order;

-- 업적 항목 등록
INSERT INTO eval_achievements (evaluation_id, review_type, sort_order, name, goal, detail, weight, score, grade)
VALUES (:evalId, :reviewType, :sortOrder, :name, :goal, :detail, :weight, :score, :grade);

-- 업적 항목 수정
UPDATE eval_achievements
SET name = :name, goal = :goal, detail = :detail, weight = :weight, score = :score, grade = :grade
WHERE id = :id;

-- 업적 항목 삭제
DELETE FROM eval_achievements WHERE id = :id;

-- ================================================================
-- [상향평가]
-- ================================================================

-- 상향평가 배정 목록 (평가자 기준)
SELECT ua.*, u.name AS target_name, u.title AS target_title
FROM upward_assignments ua
JOIN users u ON u.id = ua.target_id
WHERE ua.cycle_id = :cycleId AND ua.evaluator_id = :evaluatorId;

-- 상향평가 배정 등록
INSERT IGNORE INTO upward_assignments (id, cycle_id, evaluator_id, target_id, source)
VALUES (:id, :cycleId, :evaluatorId, :targetId, :source);

-- 상향평가 결과 저장
UPDATE upward_assignments
SET status      = 'completed',
    score       = :score,
    grade       = :grade,
    comment     = :comment,
    item_scores = :itemScores,
    submitted_at = NOW()
WHERE id = :id AND cycle_id = :cycleId;

-- 특정 대상의 상향평가 집계
SELECT
  target_id,
  COUNT(*)              AS respondent_count,
  AVG(score)            AS avg_score,
  SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_count
FROM upward_assignments
WHERE cycle_id = :cycleId AND target_id = :targetId
GROUP BY target_id;

-- ================================================================
-- [동료평가]
-- ================================================================

-- 동료평가 배정 목록 (평가자 기준)
SELECT pa.*, u.name AS target_name, u.title AS target_title
FROM peer_assignments pa
JOIN users u ON u.id = pa.target_id
WHERE pa.cycle_id = :cycleId AND pa.evaluator_id = :evaluatorId;

-- 동료평가 배정 등록
INSERT IGNORE INTO peer_assignments (id, cycle_id, evaluator_id, target_id, source)
VALUES (:id, :cycleId, :evaluatorId, :targetId, :source);

-- 동료평가 결과 저장
UPDATE peer_assignments
SET status       = 'completed',
    score        = :score,
    grade        = :grade,
    comment      = :comment,
    item_scores  = :itemScores,
    submitted_at = NOW()
WHERE id = :id AND cycle_id = :cycleId;

-- 특정 대상의 동료평가 집계
SELECT
  target_id,
  COUNT(*)  AS respondent_count,
  AVG(score) AS avg_score,
  SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_count
FROM peer_assignments
WHERE cycle_id = :cycleId AND target_id = :targetId
GROUP BY target_id;

-- ================================================================
-- [상대평가 그룹]
-- ================================================================

-- 사이클의 상대평가 그룹 전체 조회
SELECT rg.*, cu.name, cu.division, cu.team
FROM relative_groups rg
JOIN cycle_users cu ON cu.cycle_id = rg.cycle_id AND cu.user_id = rg.user_id
WHERE rg.cycle_id = :cycleId
ORDER BY rg.override_group, cu.name;

-- 상대평가 그룹 저장 (UPSERT)
INSERT INTO relative_groups (cycle_id, user_id, override_group, override_reason, locked)
VALUES (:cycleId, :userId, :overrideGroup, :overrideReason, :locked)
ON DUPLICATE KEY UPDATE
  override_group  = VALUES(override_group),
  override_reason = VALUES(override_reason),
  locked          = VALUES(locked);

-- 특정 본부장 그룹의 팀원 목록 (종합평가용)
SELECT
  e.*,
  cu.name, cu.division, cu.team,
  rg.override_group
FROM evaluations e
JOIN cycle_users cu ON cu.cycle_id = e.cycle_id AND cu.user_id = e.user_id
LEFT JOIN relative_groups rg ON rg.cycle_id = e.cycle_id AND rg.user_id = e.user_id
WHERE e.cycle_id = :cycleId
  AND (
    rg.override_group = :divisionHeadName
    OR (rg.override_group IS NULL AND cu.division = :division)
  )
  AND cu.role = 'member'
ORDER BY e.org_adj_grade, cu.name;

-- ================================================================
-- [종합평가 제출]
-- ================================================================

-- 제출 현황 조회
SELECT rs.*, cu.name AS submitted_by_name
FROM result_submissions rs
LEFT JOIN users cu ON cu.id = rs.submitted_by
WHERE rs.cycle_id = :cycleId;

-- 종합평가 제출
INSERT INTO result_submissions (cycle_id, division, submitted, submitted_at, submitted_by, distribution_reason)
VALUES (:cycleId, :division, 1, NOW(), :submittedBy, :distributionReason)
ON DUPLICATE KEY UPDATE
  submitted            = 1,
  submitted_at         = NOW(),
  submitted_by         = VALUES(submitted_by),
  distribution_reason  = VALUES(distribution_reason);

-- ================================================================
-- [평가 템플릿]
-- ================================================================

-- 템플릿 목록 (항목 수 포함)
SELECT t.*, COUNT(ti.id) AS item_count
FROM eval_templates t
LEFT JOIN template_items ti ON ti.template_id = t.id
GROUP BY t.id
ORDER BY t.template_type, t.name;

-- 템플릿 상세 (항목 포함)
SELECT t.id, t.name, t.template_type, t.role_target,
       ti.id AS item_id, ti.item_key, ti.label, ti.description,
       ti.max_score, ti.weight, ti.sort_order
FROM eval_templates t
JOIN template_items ti ON ti.template_id = t.id
WHERE t.id = :templateId
ORDER BY ti.sort_order;

-- 템플릿 등록
INSERT INTO eval_templates (id, template_type, name, description, role_target, is_default)
VALUES (:id, :templateType, :name, :description, :roleTarget, :isDefault);

-- 템플릿 항목 등록
INSERT INTO template_items (id, template_id, item_key, label, description, max_score, weight, sort_order)
VALUES (:id, :templateId, :itemKey, :label, :description, :maxScore, :weight, :sortOrder);

-- 사이클-사용자 템플릿 배정
INSERT INTO cycle_template_assignments (cycle_id, user_id, template_id, template_type)
VALUES (:cycleId, :userId, :templateId, :templateType)
ON DUPLICATE KEY UPDATE template_id = VALUES(template_id);

-- ================================================================
-- [가중치 설정]
-- ================================================================

-- 역할별 가중치 조회
SELECT * FROM role_weights ORDER BY role;

-- 역할별 가중치 저장 (UPSERT)
INSERT INTO role_weights (role, performance_weight, competency_weight, attitude_weight, upward_weight, peer_weight)
VALUES (:role, :perf, :comp, :att, :upward, :peer)
ON DUPLICATE KEY UPDATE
  performance_weight = VALUES(performance_weight),
  competency_weight  = VALUES(competency_weight),
  attitude_weight    = VALUES(attitude_weight),
  upward_weight      = VALUES(upward_weight),
  peer_weight        = VALUES(peer_weight);

-- 평가자 가중치 저장
INSERT INTO evaluator_weights (role, eval_type, weight)
VALUES (:role, :evalType, :weight)
ON DUPLICATE KEY UPDATE weight = VALUES(weight);

-- 등급 기준 저장
INSERT INTO grade_thresholds (grade, min_score)
VALUES (:grade, :minScore)
ON DUPLICATE KEY UPDATE min_score = VALUES(min_score);

-- 등급 배분 매트릭스 저장
INSERT INTO distribution_matrix (evaluator_grade, target_grade, percentage)
VALUES (:evalGrade, :targetGrade, :pct)
ON DUPLICATE KEY UPDATE percentage = VALUES(percentage);

-- ================================================================
-- [목표 관리]
-- ================================================================

-- 목표 사이클 목록
SELECT * FROM goal_cycles ORDER BY start_date DESC;

-- 특정 사이클의 사용자 목표 조회
SELECT g.*, u.name AS user_name, u.division, u.team
FROM goals g
JOIN users u ON u.id = g.user_id
WHERE g.goal_cycle_id = :goalCycleId
ORDER BY u.division, u.team, u.name, g.sort_order;

-- 목표 등록
INSERT INTO goals (id, goal_cycle_id, user_id, title, description, metric, target_value, weight, category, due_date)
VALUES (:id, :goalCycleId, :userId, :title, :description, :metric, :targetValue, :weight, :category, :dueDate);

-- 목표 수정
UPDATE goals
SET title          = :title,
    description    = :description,
    metric         = :metric,
    target_value   = :targetValue,
    current_value  = :currentValue,
    weight         = :weight,
    category       = :category,
    progress       = :progress,
    status         = :status,
    due_date       = :dueDate
WHERE id = :goalId AND user_id = :userId;

-- 목표 승인
UPDATE goals
SET approval_status = 'approved',
    approved_by     = :approvedBy,
    approved_at     = NOW()
WHERE id = :goalId;

-- 목표 반려
UPDATE goals
SET approval_status = 'rejected',
    reject_reason   = :rejectReason
WHERE id = :goalId;

-- 목표 삭제
DELETE FROM goals WHERE id = :goalId AND user_id = :userId;

-- ================================================================
-- [리포트 / 집계 쿼리]
-- ================================================================

-- 사이클 전체 평가 현황 요약
SELECT
  cu.division,
  cu.team,
  COUNT(*)                                                          AS total,
  SUM(CASE WHEN e.status_self   = 'submitted'  THEN 1 ELSE 0 END) AS self_done,
  SUM(CASE WHEN e.status_first  = 'completed'  THEN 1 ELSE 0 END) AS first_done,
  SUM(CASE WHEN e.status_second = 'completed'  THEN 1 ELSE 0 END) AS second_done,
  SUM(CASE WHEN e.published     = 1            THEN 1 ELSE 0 END) AS published
FROM evaluations e
JOIN cycle_users cu ON cu.cycle_id = e.cycle_id AND cu.user_id = e.user_id
WHERE e.cycle_id = :cycleId
GROUP BY cu.division, cu.team
ORDER BY cu.division, cu.team;

-- 등급별 인원 분포
SELECT
  COALESCE(e.org_adj_grade, e.adj_grade) AS final_grade,
  cu.division,
  COUNT(*) AS cnt
FROM evaluations e
JOIN cycle_users cu ON cu.cycle_id = e.cycle_id AND cu.user_id = e.user_id
WHERE e.cycle_id = :cycleId
  AND (e.org_adj_grade IS NOT NULL OR e.adj_grade IS NOT NULL)
GROUP BY final_grade, cu.division
ORDER BY cu.division, final_grade;

-- 본부장별 종합평가 제출 현황
SELECT
  dh.name AS division_head,
  dh.division,
  rs.submitted,
  rs.submitted_at,
  COUNT(e.id) AS member_count,
  SUM(CASE WHEN e.org_adj_grade IS NOT NULL THEN 1 ELSE 0 END) AS graded_count
FROM users dh
LEFT JOIN result_submissions rs ON rs.cycle_id = :cycleId AND rs.division = dh.division
LEFT JOIN evaluations e         ON e.cycle_id  = :cycleId
LEFT JOIN cycle_users cu        ON cu.cycle_id = e.cycle_id AND cu.user_id = e.user_id AND cu.division = dh.division AND cu.role = 'member'
WHERE dh.role = 'divisionHead' AND dh.active = 1
GROUP BY dh.id
ORDER BY dh.division;

-- 상향평가 집계 (대상자별)
SELECT
  ua.target_id,
  u.name AS target_name,
  u.title,
  COUNT(*)                                                          AS assigned,
  SUM(CASE WHEN ua.status = 'completed' THEN 1 ELSE 0 END)         AS completed,
  ROUND(AVG(CASE WHEN ua.status = 'completed' THEN ua.score END),2) AS avg_score
FROM upward_assignments ua
JOIN users u ON u.id = ua.target_id
WHERE ua.cycle_id = :cycleId
GROUP BY ua.target_id
ORDER BY u.name;

-- 동료평가 집계 (대상자별)
SELECT
  pa.target_id,
  u.name AS target_name,
  u.division, u.team,
  COUNT(*)                                                          AS assigned,
  SUM(CASE WHEN pa.status = 'completed' THEN 1 ELSE 0 END)         AS completed,
  ROUND(AVG(CASE WHEN pa.status = 'completed' THEN pa.score END),2) AS avg_score
FROM peer_assignments pa
JOIN users u ON u.id = pa.target_id
WHERE pa.cycle_id = :cycleId
GROUP BY pa.target_id
ORDER BY u.division, u.team, u.name;

-- ================================================================
-- [초기 데이터 — 기본 가중치]
-- ================================================================

INSERT INTO grade_thresholds (grade, min_score) VALUES
  ('S', 90),
  ('A', 80),
  ('B', 70),
  ('C', 60),
  ('D',  0)
ON DUPLICATE KEY UPDATE min_score = VALUES(min_score);

INSERT INTO role_weights (role, performance_weight, competency_weight, attitude_weight, upward_weight, peer_weight) VALUES
  ('member',      45, 30, 20, 0, 5),
  ('teamLead',    45, 30, 20, 0, 5),
  ('divisionHead',50, 30, 15, 0, 5),
  ('president',   60, 25, 10, 0, 5),
  ('chairman',    60, 25, 10, 0, 5)
ON DUPLICATE KEY UPDATE
  performance_weight = VALUES(performance_weight),
  competency_weight  = VALUES(competency_weight),
  attitude_weight    = VALUES(attitude_weight),
  peer_weight        = VALUES(peer_weight);

INSERT INTO evaluator_weights (role, eval_type, weight) VALUES
  ('member',       'self',   20),
  ('member',       'first',  50),
  ('member',       'second', 30),
  ('teamLead',     'self',   20),
  ('teamLead',     'first',  50),
  ('teamLead',     'second', 30),
  ('divisionHead', 'self',   30),
  ('divisionHead', 'first',  70),
  ('divisionHead', 'second',  0)
ON DUPLICATE KEY UPDATE weight = VALUES(weight);

INSERT INTO system_settings (setting_key, setting_value) VALUES
  ('peer_count',         '3'),
  ('report_visibility',  'after_publish'),
  ('company_name',       '인터로조'),
  ('system_version',     '1.0.0')
ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value);
