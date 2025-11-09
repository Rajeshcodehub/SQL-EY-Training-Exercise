USE city_library;
-- 9.1 Stored Procedure: CheckoutBook
USE city_library;
DELIMITER //
CREATE PROCEDURE CheckoutBook(
  IN p_member_id INT,
  IN p_copy_id INT,
  OUT p_due_date DATE,
  OUT p_message VARCHAR(200)
)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_is_borrowed INT;

  -- Check if member exists and is active
  SELECT status INTO v_status
  FROM members
  WHERE member_id = p_member_id;

  IF v_status IS NULL THEN
    SET p_message = 'Member does not exist.';
    SET p_due_date = NULL;
    RETURN;
  END IF;

  IF v_status <> 'active' THEN
    SET p_message = 'Member is not active. Checkout denied.';
    SET p_due_date = NULL;
    RETURN;
  END IF;

  -- Check if the book copy is already on active loan
  SELECT COUNT(*) INTO v_is_borrowed
  FROM loans
  WHERE copy_id = p_copy_id AND status = 'active';

  IF v_is_borrowed > 0 THEN
    SET p_message = 'Book copy is currently unavailable.';
    SET p_due_date = NULL;
    RETURN;
  END IF;

  -- Calculate due date (14 days from today)
  SET p_due_date = DATE_ADD(CURDATE(), INTERVAL 14 DAY);

  -- Insert loan
  INSERT INTO loans (member_id, copy_id, loan_date, due_date, status)
  VALUES (p_member_id, p_copy_id, CURDATE(), p_due_date, 'active');

  SET p_message = 'Checkout successful.';
END //
DELIMITER ;




------------------------------------------------------------
-- 9.2 Stored Procedure: ReturnBook
------------------------------------------------------------
DELIMITER //
CREATE PROCEDURE ReturnBook(
  IN p_loan_id INT,
  OUT p_fine_amount DECIMAL(10,2),
  OUT p_message VARCHAR(200)
)
BEGIN
  DECLARE v_due_date DATE;
  DECLARE v_days_late INT;

  SET p_fine_amount = 0;

  -- Get due date
  SELECT due_date INTO v_due_date
  FROM loans
  WHERE loan_id = p_loan_id;

  -- Set return date
  UPDATE loans
  SET return_date = CURDATE(), status = 'returned'
  WHERE loan_id = p_loan_id;

  -- Calculate overdue days
  SET v_days_late = DATEDIFF(CURDATE(), v_due_date);

  IF v_days_late > 0 THEN
    SET p_fine_amount = v_days_late * 2.00; -- ₹2 per day fine
    INSERT INTO fines (loan_id, fine_amount, fine_reason, paid)
    VALUES (p_loan_id, p_fine_amount, 'overdue', FALSE);
    SET p_message = CONCAT('Book returned late. Fine applied: ₹', p_fine_amount);
  ELSE
    SET p_message = 'Book returned on time. No fine.';
  END IF;

END //
DELIMITER ;

-- Test:
CALL ReturnBook(1, @fine, @msg);
SELECT @fine, @msg;



------------------------------------------------------------
-- 9.3 Function: CalculateFineDays
------------------------------------------------------------
DELIMITER //
CREATE FUNCTION CalculateFineDays(
  p_due_date DATE,
  p_return_date DATE
) RETURNS INT
DETERMINISTIC
BEGIN
  DECLARE days_late INT;
  SET days_late = DATEDIFF(p_return_date, p_due_date);
  IF days_late < 0 THEN
    RETURN 0;
  ELSE
    RETURN days_late;
  END IF;
END //
DELIMITER ;

-- Test:
SELECT loan_id, due_date, CURDATE() AS today, 
       CalculateFineDays(due_date, CURDATE()) AS overdue_days
FROM loans
WHERE status = 'active';



------------------------------------------------------------
-- 9.4 Procedure: Generate Member Report
------------------------------------------------------------
DELIMITER //
CREATE PROCEDURE GenerateMemberReport(IN p_member_id INT)
BEGIN
  -- Member Profile
  SELECT first_name, last_name, email, membership_type, status
  FROM members
  WHERE member_id = p_member_id;

  -- Active Loans
  SELECT b.title, l.loan_date, l.due_date
  FROM loans l
  JOIN book_copies bc ON l.copy_id = bc.copy_id
  JOIN books b ON bc.book_id = b.book_id
  WHERE l.member_id = p_member_id AND l.status = 'active';

  -- Outstanding Fines
  SELECT SUM(fine_amount) AS total_unpaid_fines
  FROM fines f
  JOIN loans l ON f.loan_id = l.loan_id
  WHERE l.member_id = p_member_id AND f.paid = FALSE;

  -- Upcoming Registered Events
  SELECT e.event_name, e.event_date
  FROM event_registrations er
  JOIN events e ON er.event_id = e.event_id
  WHERE er.member_id = p_member_id AND e.event_date >= CURDATE();
END //
DELIMITER ;

-- Test:
CALL GenerateMemberReport(1);
