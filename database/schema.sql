-- ================================================================
-- 인터로조 인사평가 시스템 — 데이터베이스 스키마
-- DBMS : MySQL 8.0+
-- Charset : utf8mb4 / utf8mb4_unicode_ci
-- ================================================================

CREATE DATABASE IF NOT EXISTS interojo_hr
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE interojo_hr;

-- ----------------------------------------------------------------
-- 1. 조직도 노드
-- ----------------------------------------------------------------
CREATE TABLE org_nodes (
  id           VARCHAR(50)  NOT NULL,
  name         VARCHAR(100) NOT NULL,
  parent_id    VARCHAR(50)  NULL,
  node_type    ENUM('company','division','team','unit') DEFAULT 'team',
  sort_order   INT          NOT NULL DEFAULT 0,
  created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  FOREIGN KEY fk_org_parent (parent_id) REFERENCES org_nodes(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 2. 사용자
-- ----------------------------------------------------------------
CREATE TABLE users (
  id              VARCHAR(50)  NOT NULL,
  employee_no     VARCHAR(20)  NULL,
  name            VARCHAR(50)  NOT NULL,
  email           VARCHAR(100) NULL,
  role            ENUM('admin','president','chairman','divisionHead','teamLead','member')
                  NOT NULL DEFAULT 'member',
  title           VARCHAR(50)  NULL,
  division        VARCHAR(100) NULL,
  team            VARCHAR(100) NULL,
  org_node_id     VARCHAR(50)  NULL,
  evaluator1_id   VARCHAR(50)  NULL  COMMENT '1차 평가자',
  evaluator2_id   VARCHAR(50)  NULL  COMMENT '2차 평가자',
  active          TINYINT(1)   NOT NULL DEFAULT 1,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_employee_no (employee_no),
  FOREIGN KEY fk_user_ev1  (evaluator1_id) REFERENCES users(id) ON DELETE SET NULL,
  FOREIGN KEY fk_user_ev2  (evaluator2_id) REFERENCES users(id) ON DELETE SET NULL,
  FOREIGN KEY fk_user_node (org_node_id)   REFERENCES org_nodes(id) ON DELETE SET NULL
);

-- ----------------------------------------------------------------
-- 3. 평가 사이클
-- ----------------------------------------------------------------
CREATE TABLE eval_cycles (
  id                      VARCHAR(50)  NOT NULL,
  name                    VARCHAR(100) NOT NULL,
  status                  ENUM('active','paused','done') NOT NULL DEFAULT 'paused',
  self_start              DATE NULL,
  self_end                DATE NULL,
  first_start             DATE NULL,
  first_end               DATE NULL,
  second_start            DATE NULL,
  second_end              DATE NULL,
  upward_start            DATE NULL,
  upward_end              DATE NULL,
  peer_start              DATE NULL,
  peer_end                DATE NULL,
  grade_start             DATE NULL,
  grade_end               DATE NULL,
  feedback_start          DATE NULL,
  feedback_end            DATE NULL,
  results_visible         TINYINT(1)   NOT NULL DEFAULT 0,
  use_upward              TINYINT(1)   NOT NULL DEFAULT 1,
  use_peer                TINYINT(1)   NOT NULL DEFAULT 1,
  peer_count              INT          NOT NULL DEFAULT 3,
  feedback_mgmt_unlocked  TINYINT(1)   NOT NULL DEFAULT 0,
  created_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
);

-- ----------------------------------------------------------------
-- 4. 사이클 사용자 스냅샷 (평가 시점 조직 정보 보존)
-- ----------------------------------------------------------------
CREATE TABLE cycle_users (
  id              BIGINT       NOT NULL AUTO_INCREMENT,
  cycle_id        VARCHAR(50)  NOT NULL,
  user_id         VARCHAR(50)  NOT NULL,
  employee_no     VARCHAR(20)  NULL,
  name            VARCHAR(50)  NOT NULL,
  role            VARCHAR(30)  NOT NULL,
  title           VARCHAR(50)  NULL,
  division        VARCHAR(100) NULL,
  team            VARCHAR(100) NULL,
  org_node_id     VARCHAR(50)  NULL,
  evaluator1_id   VARCHAR(50)  NULL,
  evaluator2_id   VARCHAR(50)  NULL,
  active          TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uq_cycle_user (cycle_id, user_id),
  FOREIGN KEY fk_cu_cycle (cycle_id) REFERENCES eval_cycles(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 5. 평가 (사이클 × 피평가자 1:1)
-- ----------------------------------------------------------------
CREATE TABLE evaluations (
  id                    BIGINT      NOT NULL AUTO_INCREMENT,
  cycle_id              VARCHAR(50) NOT NULL,
  user_id               VARCHAR(50) NOT NULL,
  -- 진행 상태
  status_self           ENUM('draft','submitted')                        DEFAULT 'draft',
  status_first          ENUM('pending','in_progress','completed')        DEFAULT 'pending',
  status_second         ENUM('pending','in_progress','completed')        DEFAULT 'pending',
  status_final          ENUM('pending','in_progress','completed')        DEFAULT 'pending',
  -- 1·2차 평가자 조정
  adj_grade             CHAR(1)     NULL,
  adj_grade_manual      TINYINT(1)  NOT NULL DEFAULT 0,
  adj_feedback          TEXT        NULL,
  adj_reason            TEXT        NULL,
  adj_adjusted_at       DATETIME    NULL,
  -- 종합평가(본부장) 조정
  org_adj_grade         CHAR(1)     NULL,
  org_adj_grade_manual  TINYINT(1)  NOT NULL DEFAULT 0,
  org_adj_reason        TEXT        NULL,
  org_adj_submitted_by  VARCHAR(50) NULL,
  org_adj_submitted_at  DATETIME    NULL,
  -- 결과 공개
  published             TINYINT(1)  NOT NULL DEFAULT 0,
  -- 피평가자 피드백
  result_confirmed      TINYINT(1)  NOT NULL DEFAULT 0,
  confirmed_at          DATETIME    NULL,
  opinion               TEXT        NULL,
  opinion_submitted     TINYINT(1)  NOT NULL DEFAULT 0,
  opinion_at            DATETIME    NULL,
  interview_requested   TINYINT(1)  NOT NULL DEFAULT 0,
  interview_at          DATETIME    NULL,
  -- HR 피드백 관리
  hr_status             VARCHAR(20) NULL,
  hr_confirmed          TINYINT(1)  NOT NULL DEFAULT 0,
  hr_memo               TEXT        NULL,
  hr_updated_at         DATETIME    NULL,
  created_at            DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_eval (cycle_id, user_id),
  FOREIGN KEY fk_eval_cycle (cycle_id) REFERENCES eval_cycles(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 6. 평가 리뷰 상세 (자기/1차/2차/최종 × 역량 영역)
-- ----------------------------------------------------------------
CREATE TABLE eval_reviews (
  id               BIGINT      NOT NULL AUTO_INCREMENT,
  evaluation_id    BIGINT      NOT NULL,
  review_type      ENUM('self','first','second','final') NOT NULL,
  category         ENUM('performance','competency','attitude') NOT NULL,
  score            DECIMAL(6,2) NULL,
  grade            CHAR(1)     NULL,
  comment          TEXT        NULL,
  item_scores      JSON        NULL  COMMENT '{"항목ID": 점수} 형태',
  overall_feedback TEXT        NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_review (evaluation_id, review_type, category),
  FOREIGN KEY fk_review_eval (evaluation_id) REFERENCES evaluations(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 7. 성과 업적 항목 (성과평가 세부)
-- ----------------------------------------------------------------
CREATE TABLE eval_achievements (
  id             BIGINT      NOT NULL AUTO_INCREMENT,
  evaluation_id  BIGINT      NOT NULL,
  review_type    ENUM('self','first','second','final') NOT NULL,
  sort_order     INT         NOT NULL DEFAULT 0,
  name           VARCHAR(200) NULL,
  goal           TEXT        NULL,
  detail         TEXT        NULL,
  weight         INT         NOT NULL DEFAULT 100,
  score          DECIMAL(6,2) NULL,
  grade          CHAR(1)     NULL,
  PRIMARY KEY (id),
  FOREIGN KEY fk_ach_eval (evaluation_id) REFERENCES evaluations(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 8. 상향평가 배정 및 결과
-- ----------------------------------------------------------------
CREATE TABLE upward_assignments (
  id            VARCHAR(50)  NOT NULL,
  cycle_id      VARCHAR(50)  NOT NULL,
  evaluator_id  VARCHAR(50)  NOT NULL  COMMENT '평가 실시자(부하)',
  target_id     VARCHAR(50)  NOT NULL  COMMENT '평가 대상(상급자)',
  source        VARCHAR(20)  NOT NULL DEFAULT 'organization',
  status        ENUM('pending','in_progress','completed') NOT NULL DEFAULT 'pending',
  score         DECIMAL(6,2) NULL,
  grade         CHAR(1)      NULL,
  comment       TEXT         NULL,
  item_scores   JSON         NULL,
  submitted_at  DATETIME     NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_upward (cycle_id, evaluator_id, target_id),
  FOREIGN KEY fk_upward_cycle (cycle_id) REFERENCES eval_cycles(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 9. 동료평가 배정 및 결과
-- ----------------------------------------------------------------
CREATE TABLE peer_assignments (
  id            VARCHAR(50)  NOT NULL,
  cycle_id      VARCHAR(50)  NOT NULL,
  evaluator_id  VARCHAR(50)  NOT NULL,
  target_id     VARCHAR(50)  NOT NULL,
  source        VARCHAR(20)  NOT NULL DEFAULT 'organization',
  status        ENUM('pending','in_progress','completed') NOT NULL DEFAULT 'pending',
  score         DECIMAL(6,2) NULL,
  grade         CHAR(1)      NULL,
  comment       TEXT         NULL,
  item_scores   JSON         NULL,
  submitted_at  DATETIME     NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_peer (cycle_id, evaluator_id, target_id),
  FOREIGN KEY fk_peer_cycle (cycle_id) REFERENCES eval_cycles(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 10. 평가 템플릿
-- ----------------------------------------------------------------
CREATE TABLE eval_templates (
  id            VARCHAR(50)  NOT NULL,
  template_type ENUM('performance','competency','attitude','upward','peer') NOT NULL,
  name          VARCHAR(100) NOT NULL,
  description   TEXT         NULL,
  role_target   VARCHAR(30)  NULL  COMMENT '적용 역할(member, teamLead 등, NULL=공통)',
  is_default    TINYINT(1)   NOT NULL DEFAULT 0,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
);

-- ----------------------------------------------------------------
-- 11. 템플릿 항목
-- ----------------------------------------------------------------
CREATE TABLE template_items (
  id           VARCHAR(50)  NOT NULL,
  template_id  VARCHAR(50)  NOT NULL,
  item_key     VARCHAR(100) NULL,
  label        VARCHAR(200) NOT NULL,
  description  TEXT         NULL,
  max_score    INT          NOT NULL DEFAULT 5,
  weight       DECIMAL(6,2) NOT NULL DEFAULT 1.00,
  sort_order   INT          NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  FOREIGN KEY fk_item_tmpl (template_id) REFERENCES eval_templates(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 12. 사이클별 사용자-템플릿 배정
-- ----------------------------------------------------------------
CREATE TABLE cycle_template_assignments (
  id             BIGINT      NOT NULL AUTO_INCREMENT,
  cycle_id       VARCHAR(50) NOT NULL,
  user_id        VARCHAR(50) NOT NULL,
  template_id    VARCHAR(50) NULL,
  template_type  ENUM('performance','competency','attitude') NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_cta (cycle_id, user_id, template_type),
  FOREIGN KEY fk_cta_cycle (cycle_id) REFERENCES eval_cycles(id) ON DELETE CASCADE,
  FOREIGN KEY fk_cta_tmpl  (template_id) REFERENCES eval_templates(id) ON DELETE SET NULL
);

-- ----------------------------------------------------------------
-- 13. 상대평가 그룹 (팀원 → 본부장 배정)
-- ----------------------------------------------------------------
CREATE TABLE relative_groups (
  id              BIGINT      NOT NULL AUTO_INCREMENT,
  cycle_id        VARCHAR(50) NOT NULL,
  user_id         VARCHAR(50) NOT NULL  COMMENT '팀원(member)',
  override_group  VARCHAR(50) NULL      COMMENT '배정된 본부장 이름',
  override_reason TEXT        NULL,
  locked          TINYINT(1)  NOT NULL DEFAULT 0,
  updated_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_rg (cycle_id, user_id),
  FOREIGN KEY fk_rg_cycle (cycle_id) REFERENCES eval_cycles(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 14. 종합평가 제출 (본부장)
-- ----------------------------------------------------------------
CREATE TABLE result_submissions (
  id                        BIGINT       NOT NULL AUTO_INCREMENT,
  cycle_id                  VARCHAR(50)  NOT NULL,
  division                  VARCHAR(100) NOT NULL,
  submitted                 TINYINT(1)   NOT NULL DEFAULT 0,
  submitted_at              DATETIME     NULL,
  submitted_by              VARCHAR(50)  NULL,
  distribution_reason       TEXT         NULL,
  needs_adjustment_session  TINYINT(1)  NOT NULL DEFAULT 0,
  created_at                DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_submission (cycle_id, division),
  FOREIGN KEY fk_rs_cycle (cycle_id) REFERENCES eval_cycles(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 15. 역할별 가중치 설정
-- ----------------------------------------------------------------
CREATE TABLE role_weights (
  role                VARCHAR(30) NOT NULL,
  performance_weight  INT NOT NULL DEFAULT 45,
  competency_weight   INT NOT NULL DEFAULT 30,
  attitude_weight     INT NOT NULL DEFAULT 20,
  upward_weight       INT NOT NULL DEFAULT 0,
  peer_weight         INT NOT NULL DEFAULT 5,
  PRIMARY KEY (role)
);

-- ----------------------------------------------------------------
-- 16. 평가자 가중치 설정
-- ----------------------------------------------------------------
CREATE TABLE evaluator_weights (
  role       VARCHAR(30) NOT NULL,
  eval_type  ENUM('self','first','second') NOT NULL,
  weight     DECIMAL(6,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (role, eval_type)
);

-- ----------------------------------------------------------------
-- 17. 등급 기준 점수
-- ----------------------------------------------------------------
CREATE TABLE grade_thresholds (
  grade      CHAR(1)      NOT NULL,
  min_score  DECIMAL(6,2) NOT NULL,
  PRIMARY KEY (grade)
);

-- ----------------------------------------------------------------
-- 18. 등급 배분율 매트릭스
-- ----------------------------------------------------------------
CREATE TABLE distribution_matrix (
  evaluator_grade  CHAR(1)      NOT NULL,
  target_grade     CHAR(1)      NOT NULL,
  percentage       DECIMAL(5,2) NOT NULL DEFAULT 0,
  PRIMARY KEY (evaluator_grade, target_grade)
);

-- ----------------------------------------------------------------
-- 19. 목표 사이클
-- ----------------------------------------------------------------
CREATE TABLE goal_cycles (
  id               VARCHAR(50)  NOT NULL,
  name             VARCHAR(100) NOT NULL,
  start_date       DATE         NULL,
  end_date         DATE         NULL,
  approval_enabled TINYINT(1)   NOT NULL DEFAULT 1,
  read_only        TINYINT(1)   NOT NULL DEFAULT 0,
  status           ENUM('active','paused','done') NOT NULL DEFAULT 'active',
  member_scope     ENUM('self','teamLead','team') NOT NULL DEFAULT 'team',
  created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
);

-- ----------------------------------------------------------------
-- 20. 목표
-- ----------------------------------------------------------------
CREATE TABLE goals (
  id               VARCHAR(50)  NOT NULL,
  goal_cycle_id    VARCHAR(50)  NOT NULL,
  user_id          VARCHAR(50)  NOT NULL,
  title            VARCHAR(200) NOT NULL,
  description      TEXT         NULL,
  metric           VARCHAR(200) NULL  COMMENT '측정 지표',
  target_value     VARCHAR(100) NULL  COMMENT '목표값',
  current_value    VARCHAR(100) NULL  COMMENT '현재값',
  weight           INT          NOT NULL DEFAULT 100,
  category         VARCHAR(50)  NULL,
  status           ENUM('draft','submitted','approved','rejected','in_progress','completed')
                   NOT NULL DEFAULT 'draft',
  progress         INT          NOT NULL DEFAULT 0  COMMENT '달성률 0-100',
  approval_status  ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  approved_by      VARCHAR(50)  NULL,
  approved_at      DATETIME     NULL,
  reject_reason    TEXT         NULL,
  due_date         DATE         NULL,
  created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  FOREIGN KEY fk_goal_cycle (goal_cycle_id) REFERENCES goal_cycles(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------
-- 21. 메일 발송 설정
-- ----------------------------------------------------------------
CREATE TABLE mail_settings (
  id             BIGINT       NOT NULL AUTO_INCREMENT,
  stage          VARCHAR(50)  NOT NULL  COMMENT '발송 단계(selfStart, firstStart 등)',
  enabled        TINYINT(1)   NOT NULL DEFAULT 1,
  subject        VARCHAR(200) NULL,
  body_template  TEXT         NULL,
  days_before    INT          NOT NULL DEFAULT 0  COMMENT '기간 시작 N일 전 발송',
  PRIMARY KEY (id),
  UNIQUE KEY uq_mail_stage (stage)
);

-- ----------------------------------------------------------------
-- 22. 시스템 설정 (키-값)
-- ----------------------------------------------------------------
CREATE TABLE system_settings (
  setting_key    VARCHAR(100) NOT NULL,
  setting_value  TEXT         NULL,
  updated_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (setting_key)
);
