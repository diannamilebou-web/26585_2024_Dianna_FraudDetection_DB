-- 1. SEQUENCES
CREATE SEQUENCE customer_seq       START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE device_seq         START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE agent_seq          START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE account_seq        START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE transaction_seq    START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE fraud_rule_seq     START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE fraud_flag_seq     START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE analyst_seq        START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE investigation_seq  START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE holiday_seq        START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE audit_seq          START WITH 1 INCREMENT BY 1;


-- 2. TABLE CREATION WITH CONSTRAINTS
-- CUSTOMER
CREATE TABLE customer (
  customer_id        NUMBER          DEFAULT customer_seq.NEXTVAL,
  full_name          VARCHAR2(100)   NOT NULL,
  national_id        VARCHAR2(20)    NOT NULL,
  phone_number       VARCHAR2(15)    NOT NULL,
  registration_date  DATE            DEFAULT SYSDATE NOT NULL,
  kyc_status         VARCHAR2(15)    DEFAULT 'PENDING' NOT NULL,
  CONSTRAINT pk_customer PRIMARY KEY (customer_id),
  CONSTRAINT uq_customer_natid UNIQUE (national_id),
  CONSTRAINT uq_customer_phone UNIQUE (phone_number),
  CONSTRAINT ck_customer_kyc CHECK (kyc_status IN ('PENDING','VERIFIED','REJECTED'))
);

-- DEVICE
CREATE TABLE device (
  device_id        NUMBER        DEFAULT device_seq.NEXTVAL,
  customer_id      NUMBER        NOT NULL,
  device_imei      VARCHAR2(20)  NOT NULL,
  device_type      VARCHAR2(20)  NOT NULL,
  first_seen_date  DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_device PRIMARY KEY (device_id),
  CONSTRAINT uq_device_imei UNIQUE (device_imei),
  CONSTRAINT fk_device_customer FOREIGN KEY (customer_id)
    REFERENCES customer (customer_id),
  CONSTRAINT ck_device_type CHECK (device_type IN ('SMARTPHONE','FEATURE_PHONE','TABLET','USSD'))
);

-- AGENT
CREATE TABLE agent (
  agent_id        NUMBER        DEFAULT agent_seq.NEXTVAL,
  agent_name      VARCHAR2(100) NOT NULL,
  location        VARCHAR2(100) NOT NULL,
  license_number  VARCHAR2(30)  NOT NULL,
  status          VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL,
  CONSTRAINT pk_agent PRIMARY KEY (agent_id),
  CONSTRAINT uq_agent_license UNIQUE (license_number),
  CONSTRAINT ck_agent_status CHECK (status IN ('ACTIVE','SUSPENDED','CLOSED'))
);

-- ACCOUNT
CREATE TABLE account (
  account_id      NUMBER        DEFAULT account_seq.NEXTVAL,
  customer_id     NUMBER        NOT NULL,
  account_number  VARCHAR2(20)  NOT NULL,
  balance         NUMBER(14,2)  DEFAULT 0 NOT NULL,
  status          VARCHAR2(10)  DEFAULT 'ACTIVE' NOT NULL,
  opened_date     DATE          DEFAULT SYSDATE NOT NULL,
  CONSTRAINT pk_account PRIMARY KEY (account_id),
  CONSTRAINT uq_account_number UNIQUE (account_number),
  CONSTRAINT fk_account_customer FOREIGN KEY (customer_id)
    REFERENCES customer (customer_id),
  CONSTRAINT ck_account_balance CHECK (balance >= 0),
  CONSTRAINT ck_account_status CHECK (status IN ('ACTIVE','FROZEN','CLOSED'))
);

-- TRANSACTION
CREATE TABLE transaction_ (
  transaction_id      NUMBER        DEFAULT transaction_seq.NEXTVAL,
  sender_account_id   NUMBER        NOT NULL,
  receiver_account_id NUMBER        NOT NULL,
  agent_id            NUMBER,
  device_id           NUMBER        NOT NULL,
  amount              NUMBER(14,2)  NOT NULL,
  txn_type            VARCHAR2(20)  NOT NULL,
  txn_timestamp       DATE          DEFAULT SYSDATE NOT NULL,
  status              VARCHAR2(10)  DEFAULT 'PENDING' NOT NULL,
  CONSTRAINT pk_transaction PRIMARY KEY (transaction_id),
  CONSTRAINT fk_txn_sender FOREIGN KEY (sender_account_id)
    REFERENCES account (account_id),
  CONSTRAINT fk_txn_receiver FOREIGN KEY (receiver_account_id)
    REFERENCES account (account_id),
  CONSTRAINT fk_txn_agent FOREIGN KEY (agent_id)
    REFERENCES agent (agent_id),
  CONSTRAINT fk_txn_device FOREIGN KEY (device_id)
    REFERENCES device (device_id),
  CONSTRAINT ck_txn_amount CHECK (amount > 0),
  CONSTRAINT ck_txn_type CHECK (txn_type IN ('DEPOSIT','WITHDRAWAL','TRANSFER','BILL_PAYMENT')),
  CONSTRAINT ck_txn_status CHECK (status IN ('PENDING','COMPLETED','REVERSED','BLOCKED')),
  CONSTRAINT ck_txn_sender_receiver CHECK (sender_account_id <> receiver_account_id)
);

-- FRAUD_RULE
CREATE TABLE fraud_rule (
  rule_id           NUMBER        DEFAULT fraud_rule_seq.NEXTVAL,
  rule_name         VARCHAR2(60)  NOT NULL,
  rule_description  VARCHAR2(300) NOT NULL,
  threshold_value   NUMBER(14,2)  NOT NULL,
  severity_level    VARCHAR2(10)  NOT NULL,
  is_active         CHAR(1)       DEFAULT 'Y' NOT NULL,
  CONSTRAINT pk_fraud_rule PRIMARY KEY (rule_id),
  CONSTRAINT uq_fraud_rule_name UNIQUE (rule_name),
  CONSTRAINT ck_rule_severity CHECK (severity_level IN ('LOW','MEDIUM','HIGH','CRITICAL')),
  CONSTRAINT ck_rule_active CHECK (is_active IN ('Y','N'))
);

-- ANALYST
CREATE TABLE analyst (
  analyst_id  NUMBER        DEFAULT analyst_seq.NEXTVAL,
  name        VARCHAR2(100) NOT NULL,
  role        VARCHAR2(30)  NOT NULL,
  email       VARCHAR2(100) NOT NULL,
  CONSTRAINT pk_analyst PRIMARY KEY (analyst_id),
  CONSTRAINT uq_analyst_email UNIQUE (email),
  CONSTRAINT ck_analyst_role CHECK (role IN ('FRAUD_ANALYST','RISK_MANAGER','COMPLIANCE_OFFICER','ADMIN'))
);

-- FRAUD_FLAG
CREATE TABLE fraud_flag (
  flag_id             NUMBER        DEFAULT fraud_flag_seq.NEXTVAL,
  transaction_id      NUMBER        NOT NULL,
  rule_id             NUMBER        NOT NULL,
  risk_score          NUMBER(5,2)   NOT NULL,
  flagged_date        DATE          DEFAULT SYSDATE NOT NULL,
  resolution_status   VARCHAR2(15)  DEFAULT 'OPEN' NOT NULL,
  CONSTRAINT pk_fraud_flag PRIMARY KEY (flag_id),
  CONSTRAINT fk_flag_transaction FOREIGN KEY (transaction_id)
    REFERENCES transaction_ (transaction_id),
  CONSTRAINT fk_flag_rule FOREIGN KEY (rule_id)
    REFERENCES fraud_rule (rule_id),
  CONSTRAINT ck_flag_score CHECK (risk_score BETWEEN 0 AND 100),
  CONSTRAINT ck_flag_status CHECK (resolution_status IN ('OPEN','UNDER_REVIEW','CONFIRMED_FRAUD','FALSE_POSITIVE'))
);

-- INVESTIGATION
CREATE TABLE investigation (
  investigation_id  NUMBER        DEFAULT investigation_seq.NEXTVAL,
  flag_id           NUMBER        NOT NULL,
  analyst_id        NUMBER        NOT NULL,
  notes             VARCHAR2(500),
  outcome           VARCHAR2(20),
  closed_date       DATE,
  CONSTRAINT pk_investigation PRIMARY KEY (investigation_id),
  CONSTRAINT uq_investigation_flag UNIQUE (flag_id),
  CONSTRAINT fk_invest_flag FOREIGN KEY (flag_id)
    REFERENCES fraud_flag (flag_id),
  CONSTRAINT fk_invest_analyst FOREIGN KEY (analyst_id)
    REFERENCES analyst (analyst_id),
  CONSTRAINT ck_invest_outcome CHECK (outcome IN ('FRAUD_CONFIRMED','FALSE_POSITIVE','INCONCLUSIVE') OR outcome IS NULL)
);

-- PUBLIC_HOLIDAY
CREATE TABLE public_holiday (
  holiday_id   NUMBER        DEFAULT holiday_seq.NEXTVAL,
  holiday_date DATE          NOT NULL,
  description  VARCHAR2(100) NOT NULL,
  CONSTRAINT pk_holiday PRIMARY KEY (holiday_id),
  CONSTRAINT uq_holiday_date UNIQUE (holiday_date)
);

-- AUDIT_LOG
CREATE TABLE audit_log (
  audit_id      NUMBER        DEFAULT audit_seq.NEXTVAL,
  table_name    VARCHAR2(30)  NOT NULL,
  operation     VARCHAR2(10)  NOT NULL,
  performed_by  NUMBER,
  performed_on  DATE          DEFAULT SYSDATE NOT NULL,
  old_value     VARCHAR2(500),
  new_value     VARCHAR2(500),
  CONSTRAINT pk_audit PRIMARY KEY (audit_id),
  CONSTRAINT fk_audit_analyst FOREIGN KEY (performed_by)
    REFERENCES analyst (analyst_id),
  CONSTRAINT ck_audit_operation CHECK (operation IN ('INSERT','UPDATE','DELETE'))
);

-- 3. SAMPLE DATA
-- Customers
INSERT INTO customer (full_name, national_id, phone_number, kyc_status)
VALUES ('Reine makaga', 'RW1199012345678', '+250788123456', 'VERIFIED');
INSERT INTO customer (full_name, national_id, phone_number, kyc_status)
VALUES ('Alexis douckaga', 'RW1198765432109', '+250788234567', 'VERIFIED');
INSERT INTO customer (full_name, national_id, phone_number, kyc_status)
VALUES ('Eric miyakou', 'RW1197712340987', '+250788345678', 'PENDING');

-- Devices
INSERT INTO device (customer_id, device_imei, device_type)
VALUES (1, '356938035643809', 'SMARTPHONE');
INSERT INTO device (customer_id, device_imei, device_type)
VALUES (2, '356938035643810', 'SMARTPHONE');
INSERT INTO device (customer_id, device_imei, device_type)
VALUES (3, '356938035643811', 'FEATURE_PHONE');

-- Agents
INSERT INTO agent (agent_name, location, license_number, status)
VALUES ('Kigali City Agent 01', 'Kigali - Nyarugenge', 'LIC-2026-001', 'ACTIVE');
INSERT INTO agent (agent_name, location, license_number, status)
VALUES ('Musanze Agent 07', 'Musanze', 'LIC-2026-007', 'ACTIVE');

-- Accounts
INSERT INTO account (customer_id, account_number, balance, status)
VALUES (1, 'ACC-0001-2026', 150000, 'ACTIVE');
INSERT INTO account (customer_id, account_number, balance, status)
VALUES (2, 'ACC-0002-2026', 50000, 'ACTIVE');
INSERT INTO account (customer_id, account_number, balance, status)
VALUES (3, 'ACC-0003-2026', 5000, 'ACTIVE');

-- Fraud rules
INSERT INTO fraud_rule (rule_name, rule_description, threshold_value, severity_level)
VALUES ('LARGE_SINGLE_TXN', 'Single transaction exceeds 500,000 RWF', 500000, 'HIGH');
INSERT INTO fraud_rule (rule_name, rule_description, threshold_value, severity_level)
VALUES ('RAPID_SMURFING', 'More than 5 small transactions from same account within 10 minutes', 5, 'MEDIUM');
INSERT INTO fraud_rule (rule_name, rule_description, threshold_value, severity_level)
VALUES ('NEW_DEVICE_HIGH_VALUE', 'High value transaction from a device seen for the first time', 200000, 'CRITICAL');

-- Analysts
INSERT INTO analyst (name, role, email)
VALUES ('Tine madoungou', 'FRAUD_ANALYST', 'tine.madoungou@fraudops.rw');
INSERT INTO analyst (name, role, email)
VALUES ('Patrick Ngema', 'RISK_MANAGER', 'patrick.ngema@fraudops.rw');

-- Public holidays
INSERT INTO public_holiday (holiday_date, description) VALUES (DATE '2026-01-01', 'New Year');
INSERT INTO public_holiday (holiday_date, description) VALUES (DATE '2026-04-07', 'Genocide Memorial Day');
INSERT INTO public_holiday (holiday_date, description) VALUES (DATE '2026-07-01', 'Independence Day');

-- Transactions
INSERT INTO transaction_ (sender_account_id, receiver_account_id, agent_id, device_id, amount, txn_type, status)
VALUES (1, 2, 1, 1, 25000, 'TRANSFER', 'COMPLETED');
INSERT INTO transaction_ (sender_account_id, receiver_account_id, agent_id, device_id, amount, txn_type, status)
VALUES (2, 3, NULL, 2, 700000, 'TRANSFER', 'COMPLETED');
INSERT INTO transaction_ (sender_account_id, receiver_account_id, agent_id, device_id, amount, txn_type, status)
VALUES (1, 3, 2, 3, 10000, 'BILL_PAYMENT', 'COMPLETED');

-- Fraud flag
INSERT INTO fraud_flag (transaction_id, rule_id, risk_score, resolution_status)
VALUES (2, 1, 88.5, 'OPEN');

-- Investigation
INSERT INTO investigation (flag_id, analyst_id, notes, outcome, closed_date)
VALUES (1, 1, 'Reviewing large transfer, contacting customer for verification.', NULL, NULL);

COMMIT;


-- 4. VERIFICATION QUERIES

SELECT table_name FROM user_tables ORDER BY table_name;
SELECT customer_id, full_name, kyc_status FROM customer;
SELECT transaction_id, amount, txn_type, status FROM transaction_;
SELECT flag_id, transaction_id, risk_score, resolution_status FROM fraud_flag;