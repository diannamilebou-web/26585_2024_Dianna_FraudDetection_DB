SET SERVEROUTPUT ON;


-- 1. BUSINESS RULE TRIGGER (compound trigger)

CREATE OR REPLACE TRIGGER trg_block_weekday_holiday_dml
FOR INSERT OR UPDATE OR DELETE ON transaction_
COMPOUND TRIGGER

  v_day_name    VARCHAR2(10);
  v_is_holiday  NUMBER;

  BEFORE STATEMENT IS
  BEGIN
    v_day_name := TRIM(TO_CHAR(SYSDATE, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH'));

    SELECT COUNT(*) INTO v_is_holiday
    FROM public_holiday
    WHERE holiday_date = TRUNC(SYSDATE);

    IF v_day_name NOT IN ('SAT','SUN') THEN
      RAISE_APPLICATION_ERROR(-20100,
        'DML on transaction_ is blocked on weekdays (Mon-Fri). Today is ' || v_day_name || '.');
    ELSIF v_is_holiday > 0 THEN
      RAISE_APPLICATION_ERROR(-20101,
        'DML on transaction_ is blocked: today is a public holiday.');
    END IF;
  END BEFORE STATEMENT;

END trg_block_weekday_holiday_dml;
/




-- 2. AUDIT TRIGGERS


CREATE OR REPLACE TRIGGER trg_audit_account
AFTER INSERT OR UPDATE OR DELETE ON account
FOR EACH ROW
DECLARE
  v_operation VARCHAR2(10);
  v_old_val   VARCHAR2(500);
  v_new_val   VARCHAR2(500);
BEGIN
  IF INSERTING THEN
    v_operation := 'INSERT';
    v_old_val   := NULL;
    v_new_val   := 'account_id=' || :NEW.account_id || ', balance=' || :NEW.balance || ', status=' || :NEW.status;
  ELSIF UPDATING THEN
    v_operation := 'UPDATE';
    v_old_val   := 'balance=' || :OLD.balance || ', status=' || :OLD.status;
    v_new_val   := 'balance=' || :NEW.balance || ', status=' || :NEW.status;
  ELSIF DELETING THEN
    v_operation := 'DELETE';
    v_old_val   := 'account_id=' || :OLD.account_id || ', balance=' || :OLD.balance;
    v_new_val   := NULL;
  END IF;

  INSERT INTO audit_log (table_name, operation, performed_by, performed_on, old_value, new_value)
  VALUES ('ACCOUNT', v_operation, NULL, SYSDATE, v_old_val, v_new_val);
EXCEPTION
  WHEN OTHERS THEN
    NULL; 
END trg_audit_account;
/


CREATE OR REPLACE TRIGGER trg_audit_fraud_flag
AFTER INSERT OR UPDATE OR DELETE ON fraud_flag
FOR EACH ROW
DECLARE
  v_operation VARCHAR2(10);
  v_old_val   VARCHAR2(500);
  v_new_val   VARCHAR2(500);
BEGIN
  IF INSERTING THEN
    v_operation := 'INSERT';
    v_new_val   := 'flag_id=' || :NEW.flag_id || ', status=' || :NEW.resolution_status;
  ELSIF UPDATING THEN
    v_operation := 'UPDATE';
    v_old_val   := 'status=' || :OLD.resolution_status;
    v_new_val   := 'status=' || :NEW.resolution_status;
  ELSIF DELETING THEN
    v_operation := 'DELETE';
    v_old_val   := 'flag_id=' || :OLD.flag_id;
  END IF;

  INSERT INTO audit_log (table_name, operation, performed_by, performed_on, old_value, new_value)
  VALUES ('FRAUD_FLAG', v_operation, NULL, SYSDATE, v_old_val, v_new_val);
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END trg_audit_fraud_flag;
/


-- 3. USER ACTIVITY TRACKING TRIGGER

CREATE TABLE session_log (
  session_log_id  NUMBER GENERATED ALWAYS AS IDENTITY,
  db_username     VARCHAR2(60),
  os_user         VARCHAR2(60),
  login_time      DATE DEFAULT SYSDATE,
  host_machine    VARCHAR2(100),
  CONSTRAINT pk_session_log PRIMARY KEY (session_log_id)
);

CREATE OR REPLACE TRIGGER trg_track_logon
AFTER LOGON ON SCHEMA
BEGIN
  INSERT INTO session_log (db_username, os_user, host_machine)
  VALUES (
    SYS_CONTEXT('USERENV','SESSION_USER'),
    SYS_CONTEXT('USERENV','OS_USER'),
    SYS_CONTEXT('USERENV','HOST')
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END trg_track_logon;
/


-- 4. SECURITY RESTRICTION EXAMPLE


CREATE OR REPLACE TRIGGER trg_protect_customer_delete
BEFORE DELETE ON customer
FOR EACH ROW
BEGIN
  IF USER != 'DIANNA_26585_2024_FRAUDDETECTION_DB' THEN
    RAISE_APPLICATION_ERROR(-20200, 'Deleting customers is restricted to the schema owner.');
  END IF;
END trg_protect_customer_delete;
/


-- 5. VERIFICATION


UPDATE account SET balance = balance - 5000 WHERE account_id = 1;
COMMIT;

SELECT audit_id, table_name, operation, performed_on, old_value, new_value
FROM audit_log ORDER BY audit_id;

SELECT trigger_name, status FROM user_triggers ORDER BY trigger_name;


SELECT * FROM session_log ORDER BY login_time DESC;