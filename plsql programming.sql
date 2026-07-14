SET SERVEROUTPUT ON;


-- 1. STANDALONE FUNCTION

CREATE OR REPLACE FUNCTION fn_calculate_risk_score (
  p_transaction_id IN transaction_.transaction_id%TYPE
) RETURN NUMBER
IS
  v_amount        transaction_.amount%TYPE;
  v_device_id     transaction_.device_id%TYPE;
  v_first_seen    device.first_seen_date%TYPE;
  v_score         NUMBER := 0;
  v_txn_count     NUMBER;
  e_txn_not_found EXCEPTION;
BEGIN
  BEGIN
    SELECT amount, device_id
    INTO v_amount, v_device_id
    FROM transaction_
    WHERE transaction_id = p_transaction_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE e_txn_not_found;
  END;


  IF v_amount > 500000 THEN
    v_score := v_score + 50;
  ELSIF v_amount > 200000 THEN
    v_score := v_score + 25;
  END IF;

  
  SELECT first_seen_date INTO v_first_seen
  FROM device WHERE device_id = v_device_id;

  IF v_first_seen >= SYSDATE - 1 THEN
    v_score := v_score + 30;
  END IF;

  
  SELECT COUNT(*) INTO v_txn_count
  FROM transaction_
  WHERE device_id = v_device_id
    AND txn_timestamp >= SYSDATE - (10/1440);

  IF v_txn_count > 5 THEN
    v_score := v_score + 20;
  END IF;

  IF v_score > 100 THEN
    v_score := 100;
  END IF;

  RETURN v_score;

EXCEPTION
  WHEN e_txn_not_found THEN
    DBMS_OUTPUT.PUT_LINE('Error: transaction ' || p_transaction_id || ' not found.');
    RETURN NULL;
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Unexpected error in fn_calculate_risk_score: ' || SQLERRM);
    RETURN NULL;
END fn_calculate_risk_score;
/


-- 2. STANDALONE PROCEDURE (parameterized)

CREATE OR REPLACE PROCEDURE pr_register_transaction (
  p_sender_account   IN  NUMBER,
  p_receiver_account IN  NUMBER,
  p_agent_id         IN  NUMBER,
  p_device_id        IN  NUMBER,
  p_amount           IN  NUMBER,
  p_txn_type         IN  VARCHAR2,
  p_new_txn_id       OUT NUMBER
)
IS
  v_risk_score     NUMBER;
  v_rule_id        fraud_rule.rule_id%TYPE;

  CURSOR c_active_rules IS
    SELECT rule_id, rule_name, threshold_value
    FROM fraud_rule
    WHERE is_active = 'Y';

  e_same_account   EXCEPTION;
  e_invalid_amount EXCEPTION;
BEGIN
  IF p_sender_account = p_receiver_account THEN
    RAISE e_same_account;
  END IF;

  IF p_amount <= 0 THEN
    RAISE e_invalid_amount;
  END IF;

  INSERT INTO transaction_ (
    sender_account_id, receiver_account_id, agent_id,
    device_id, amount, txn_type, status
  ) VALUES (
    p_sender_account, p_receiver_account, p_agent_id,
    p_device_id, p_amount, p_txn_type, 'COMPLETED'
  )
  RETURNING transaction_id INTO p_new_txn_id;

  v_risk_score := fn_calculate_risk_score(p_new_txn_id);

  FOR rule_rec IN c_active_rules LOOP
    IF rule_rec.rule_name = 'LARGE_SINGLE_TXN' AND p_amount > rule_rec.threshold_value THEN
      INSERT INTO fraud_flag (transaction_id, rule_id, risk_score, resolution_status)
      VALUES (p_new_txn_id, rule_rec.rule_id, v_risk_score, 'OPEN');
    END IF;
  END LOOP;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Transaction ' || p_new_txn_id || ' registered. Risk score: ' || v_risk_score);

EXCEPTION
  WHEN e_same_account THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Error: sender and receiver accounts must differ.');
    RAISE_APPLICATION_ERROR(-20001, 'Sender and receiver account cannot be the same.');
  WHEN e_invalid_amount THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Error: transaction amount must be positive.');
    RAISE_APPLICATION_ERROR(-20002, 'Transaction amount must be greater than zero.');
  WHEN OTHERS THEN
    ROLLBACK;
    DBMS_OUTPUT.PUT_LINE('Unexpected error in pr_register_transaction: ' || SQLERRM);
    RAISE;
END pr_register_transaction;
/


-- 3. PACKAGE: fraud_pkg

CREATE OR REPLACE PACKAGE fraud_pkg AS

  PROCEDURE register_transaction (
    p_sender_account   IN  NUMBER,
    p_receiver_account IN  NUMBER,
    p_agent_id         IN  NUMBER,
    p_device_id        IN  NUMBER,
    p_amount           IN  NUMBER,
    p_txn_type         IN  VARCHAR2,
    p_new_txn_id       OUT NUMBER
  );

  PROCEDURE open_investigation (
    p_flag_id      IN NUMBER,
    p_analyst_id   IN NUMBER,
    p_notes        IN VARCHAR2
  );

  PROCEDURE close_investigation (
    p_investigation_id IN NUMBER,
    p_outcome          IN VARCHAR2
  );

  FUNCTION get_open_flag_count RETURN NUMBER;

END fraud_pkg;
/

CREATE OR REPLACE PACKAGE BODY fraud_pkg AS

  PROCEDURE register_transaction (
    p_sender_account   IN  NUMBER,
    p_receiver_account IN  NUMBER,
    p_agent_id         IN  NUMBER,
    p_device_id        IN  NUMBER,
    p_amount           IN  NUMBER,
    p_txn_type         IN  VARCHAR2,
    p_new_txn_id       OUT NUMBER
  ) IS
  BEGIN
    pr_register_transaction(
      p_sender_account, p_receiver_account, p_agent_id,
      p_device_id, p_amount, p_txn_type, p_new_txn_id
    );
  END register_transaction;

  PROCEDURE open_investigation (
    p_flag_id    IN NUMBER,
    p_analyst_id IN NUMBER,
    p_notes      IN VARCHAR2
  ) IS
    v_exists NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_exists FROM fraud_flag WHERE flag_id = p_flag_id;
    IF v_exists = 0 THEN
      RAISE_APPLICATION_ERROR(-20010, 'Fraud flag ' || p_flag_id || ' does not exist.');
    END IF;

    INSERT INTO investigation (flag_id, analyst_id, notes)
    VALUES (p_flag_id, p_analyst_id, p_notes);

    UPDATE fraud_flag SET resolution_status = 'UNDER_REVIEW' WHERE flag_id = p_flag_id;

    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('Error in open_investigation: ' || SQLERRM);
      RAISE;
  END open_investigation;

  PROCEDURE close_investigation (
    p_investigation_id IN NUMBER,
    p_outcome          IN VARCHAR2
  ) IS
    v_flag_id NUMBER;
  BEGIN
    IF p_outcome NOT IN ('FRAUD_CONFIRMED','FALSE_POSITIVE','INCONCLUSIVE') THEN
      RAISE_APPLICATION_ERROR(-20011, 'Invalid outcome value: ' || p_outcome);
    END IF;

    UPDATE investigation
    SET outcome = p_outcome, closed_date = SYSDATE
    WHERE investigation_id = p_investigation_id
    RETURNING flag_id INTO v_flag_id;

    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20012, 'Investigation ' || p_investigation_id || ' not found.');
    END IF;

    UPDATE fraud_flag
    SET resolution_status = CASE p_outcome
                               WHEN 'FRAUD_CONFIRMED' THEN 'CONFIRMED_FRAUD'
                               WHEN 'FALSE_POSITIVE'  THEN 'FALSE_POSITIVE'
                               ELSE 'UNDER_REVIEW'
                             END
    WHERE flag_id = v_flag_id;

    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('Error in close_investigation: ' || SQLERRM);
      RAISE;
  END close_investigation;

  FUNCTION get_open_flag_count RETURN NUMBER IS
    v_count NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_count FROM fraud_flag WHERE resolution_status = 'OPEN';
    RETURN v_count;
  END get_open_flag_count;

END fraud_pkg;
/


-- 4. TEST / DEMO CALLS



DECLARE
  v_txn_id NUMBER;
BEGIN
  fraud_pkg.register_transaction(1, 2, 1, 1, 15000, 'TRANSFER', v_txn_id);
  DBMS_OUTPUT.PUT_LINE('New transaction id: ' || v_txn_id);
END;
/


DECLARE
  v_txn_id NUMBER;
BEGIN
  fraud_pkg.register_transaction(2, 3, NULL, 2, 900000, 'TRANSFER', v_txn_id);
  DBMS_OUTPUT.PUT_LINE('New transaction id: ' || v_txn_id);
END;
/


DECLARE
  v_txn_id NUMBER;
BEGIN
  fraud_pkg.register_transaction(1, 1, 1, 1, 5000, 'TRANSFER', v_txn_id);
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Caught expected error: ' || SQLERRM);
END;
/


BEGIN
  DBMS_OUTPUT.PUT_LINE('Open flags before: ' || fraud_pkg.get_open_flag_count);
END;
/


BEGIN
  fraud_pkg.open_investigation(1, 1, 'Automated PL/SQL test investigation.');
END;
/


DECLARE
  v_inv_id NUMBER;
BEGIN
  SELECT investigation_id INTO v_inv_id FROM investigation WHERE flag_id = 1;
  fraud_pkg.close_investigation(v_inv_id, 'FALSE_POSITIVE');
END;
/

BEGIN
  DBMS_OUTPUT.PUT_LINE('Open flags after: ' || fraud_pkg.get_open_flag_count);
END;
/


-- 5. VERIFICATION QUERIES

SELECT transaction_id, amount, status FROM transaction_ ORDER BY transaction_id;
SELECT flag_id, transaction_id, risk_score, resolution_status FROM fraud_flag ORDER BY flag_id;
SELECT investigation_id, flag_id, outcome, closed_date FROM investigation ORDER BY investigation_id;