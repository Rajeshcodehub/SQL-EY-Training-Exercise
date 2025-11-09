-- Transaction 1: Safe Book Checkout
START TRANSACTION;

-- Step 1: Find available copy
SELECT copyid INTO @available_copy
FROM bookcopies
WHERE bookid = 1
AND copyid NOT IN (SELECT copyid FROM loans WHERE status = 'active')
LIMIT 1;

-- Step 2: Create loan record
INSERT INTO loans (memberid, copyid, loandate, duedate, status)
VALUES (1, @available_copy, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY), 'active');

-- Step 3: Log the action
INSERT INTO auditlog (tablename, action, recordid, description) 
VALUES ('loans', 'INSERT', LAST_INSERT_ID(), 'Book checked out');

COMMIT;

-- Transaction 2: Process Fine Payment
START TRANSACTION;

-- Step 1: Mark fine as paid
UPDATE fines
SET paid = TRUE, paymentdate = CURDATE()
WHERE fineid = 1;

-- Step 2: Log payment
INSERT INTO auditlog (tablename, action, recordid, description)
VALUES ('fines', 'UPDATE', 1, 'Fine paid');

-- Step 3: Reactivate member if no outstanding fines
UPDATE members
SET status = 'active'
WHERE memberid = (SELECT l.memberid FROM fines f JOIN loans l ON f.loanid = l.loanid WHERE f.fineid = 1)
AND NOT EXISTS (
  SELECT 1 FROM fines f2 
  JOIN loans l2 ON f2.loanid = l2.loanid
  WHERE l2.memberid = members.memberid AND f2.paid = FALSE
);

COMMIT;

-- Transaction 3: Rollback Example with Condition
START TRANSACTION;

INSERT INTO loans (memberid, copyid, loandate, duedate, status) 
VALUES (1, 5, CURDATE(), DATE_ADD(CURDATE(), INTERVAL 14 DAY), 'active');

-- Simulate check for too many loans
SELECT COUNT(*) INTO @active_count 
FROM loans 
WHERE memberid = 1 AND status = 'active';

IF @active_count > 5 THEN
  ROLLBACK;
ELSE
  COMMIT;
END IF;

-- Transaction 4: Batch Book Return
START TRANSACTION;

-- Return all active loans for a member
UPDATE loans 
SET status = 'returned', returndate = CURDATE()
WHERE memberid = 1 AND status = 'active';

-- Calculate and insert fines for overdue returns
INSERT INTO fines (loanid, fineamount, finereason, paid)
SELECT loanid, GREATEST(0, DATEDIFF(CURDATE(), duedate)) * 0.25, 'overdue', FALSE
FROM loans
WHERE memberid = 1 AND status = 'returned' AND returndate > duedate
AND loanid NOT IN (SELECT loanid FROM fines);

-- Log batch return
INSERT INTO auditlog (tablename, action, recordid, description)
VALUES ('loans', 'UPDATE', 1, 'Batch return for member 1');

COMMIT;