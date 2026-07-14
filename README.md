# 26585_2024_Dianna_FraudDetection_DB

## 1. Problem Statement

Mobile money platforms process massive transaction volumes daily. Manual review cannot keep pace with fraud patterns such as SIM-swap fraud, agent collusion, and rapid micro-transaction "smurfing."
# Context of use: 
Deployed within a mobile money operator's Risk & Compliance department, integrated with transaction processing and agent networks.
# Target users: 
Fraud analysts, risk managers, compliance officers, database/system administrators.
# Objectives: 
Model customers, agents, devices, accounts, and transactions relationally; score transactions with rule-based and statistical anomaly checks; flag, queue, and track investigation of suspicious activity; enforce business rules via triggers; maintain a full audit trail; deliver an analytics dashboard on fraud trends.
# Expected benefits: 
Faster fraud detection and response time, reduced financial losses, an audit-ready compliance trail, and data-driven insight into fraud patterns.


## 2. Business Process Modeling

# Scope: 
The fraud detection lifecycle, from the moment a mobile money transaction is initiated until a fraud case is resolved.

# Actors: 
Customer, Mobile Money Agent, the Database System (automated scoring), Fraud Analyst, Risk Manager.

# Workflow (swimlanes):
# Customer
initiates a transaction (transfer, deposit, withdrawal, or bill payment) via app or USSD, sometimes through an Agent.
# System 
records the transaction (transaction_ table), runs fn_calculate_risk_score, and checks it against all active fraud_rule entries via pr_register_transaction.
If a threshold is breached, the System automatically creates a fraud_flag record with resolution_status = OPEN.
# A Fraud Analyst
Picks up the open flag, opens an investigation, and records notes.
# The Analyst or Risk Manager
closes the investigation with an outcome (FRAUD_CONFIRMED, FALSE_POSITIVE, or INCONCLUSIVE), which updates the flag's resolution status.
Every step — account changes, flag status changes, logons — is written to audit_log / session_log for compliance review.

The BPMN swimlane diagram is 
(business_process_modeling image).

3. Logical Database Design (3NF)

Entities: CUSTOMER, DEVICE, AGENT, ACCOUNT, TRANSACTION_, FRAUD_RULE, FRAUD_FLAG, ANALYST, INVESTIGATION, PUBLIC_HOLIDAY, AUDIT_LOG, SESSION_LOG.

Key relationships:


One customer → many accounts, many devices (1:M)
One transaction → sender account, receiver account, optional agent, and device (FK links)
One transaction → zero or more fraud flags; each flag references the rule that triggered it
One fraud flag → at most one investigation, handled by one analyst


Why this is in 3NF:


1NF: every attribute is atomic — no repeating groups or comma-separated values in any column.
2NF: every table uses a single-column surrogate primary key (_id), so no partial dependency is possible.
3NF: no transitive dependencies — e.g. agent_name and location live only in AGENT, not repeated on every TRANSACTION_ row; a transaction only stores agent_id and looks the rest up via the foreign key.


The full ER diagram is in 03_logical_design/.

4. Database Creation

04_database_creation/phase4_database_creation.sql — creates the tablespace, schema user (Dianna_26585_2024_FraudDetection_DB), and grants privileges (session, table, view, sequence, procedure, trigger, synonym).

5. Table Implementation

05_table_implementation/phase5_table_implementation.sql — creates all 11 tables with PK/FK/NOT NULL/UNIQUE/CHECK constraints, plus meaningful sample data.

6. PL/SQL Programming

06_plsql/phase6_plsql.sql — includes:


fn_calculate_risk_score (function)
pr_register_transaction (parameterized procedure with cursor + exception handling)
fraud_pkg (package: register/investigate/close/report)
Demo test calls with expected outputs


7. Triggers, Auditing & Security

07_triggers_audit/phase7_triggers_audit.sql — includes:


trg_block_weekday_holiday_dml — compound trigger enforcing the mandatory business rule (blocks DML on weekdays and public holidays)
trg_audit_account, trg_audit_fraud_flag — row-level audit logging
trg_track_logon — user activity/session tracking
trg_protect_customer_delete — security restriction example


8. Innovation Component

The innovation layer is a Power BI dashboard connected directly to the Oracle schema, giving fraud analysts a live view of system activity beyond raw SQL output. It includes:


Fraud trend overview — flagged transactions over time, broken down by severity level (LOW/MEDIUM/HIGH/CRITICAL)
Risk score distribution — histogram of fraud_flag.risk_score across all flagged transactions
Rule performance — which fraud_rule entries trigger the most flags, to evaluate rule effectiveness
Investigation funnel — how many flags are OPEN vs UNDER_REVIEW vs CONFIRMED_FRAUD vs FALSE_POSITIVE
Agent/device risk map — transaction volume and flag rate by agent location and device type


Connection: Power BI's Oracle connector, pointed at the ORCLPDB service, authenticated as a read-only account granted SELECT on transaction_, fraud_flag, fraud_rule, and investigation (via the fraud_analyst_role created in Phase IV).

Files and the .pbix dashboard are stored in innovation/.
