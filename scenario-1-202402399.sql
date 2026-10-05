DROP TABLE IF EXISTS book_loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;
DROP PROCEDURE IF EXISTS borrow_book(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS return_book(INT);


CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL,
    loan_status    VARCHAR(20) NOT NULL DEFAULT 'BORROWED'
);

INSERT INTO books (title, available_copies) VALUES
    ('Database System Concepts', 5),
    ('Operating System Concepts', 2),
    ('Computer Networks', 0);

SELECT * FROM books ORDER BY book_id;


DO $$
DECLARE
    rec RECORD;
BEGIN
    -- checks one book at a time (all three books so every branch shows)
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '%: UNAVAILABLE (0 copies)', rec.title;
        ELSIF rec.available_copies <= 2 THEN
            RAISE NOTICE '%: LOW on copies (% left)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '%: sufficiently stocked (% copies)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;

DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number %', n;
        n := n + 1;
    END LOOP;

    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number %', shelf;
    END LOOP;
END $$;


CREATE OR REPLACE PROCEDURE borrow_book(p_book_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_avail INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty;
    END IF;

    SELECT available_copies INTO v_avail
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    IF v_avail < p_qty THEN
        RAISE NOTICE 'Loan rejected for student %: requested %, only % available',
                     p_student, p_qty, v_avail;
        RETURN;
    END IF;

    UPDATE books SET available_copies = available_copies - p_qty
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student, p_qty, 'BORROWED');

    RAISE NOTICE 'Loan recorded: student % borrowed % copy/copies of book %',
                 p_student, p_qty, p_book_id;
END $$;


CALL borrow_book(1, '202400101', 2);   -- valid
CALL borrow_book(2, '202400102', 1);   -- valid
CALL borrow_book(1, '202400103', 10);  -- exceeds available copies (rejected)

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;


CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status  VARCHAR(20);
    v_qty     INT;
    v_book_id INT;
BEGIN
    SELECT loan_status, quantity, book_id
    INTO v_status, v_qty, v_book_id
    FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist', p_loan_id;
        RETURN;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned, no copies restored', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned, % copy/copies restored', p_loan_id, v_qty;
END $$;

CALL return_book(1);   -- first call: restores copies
CALL return_book(1);   -- second call: nothing happens

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;


DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT title, available_copies FROM books
        WHERE available_copies <= 2 ORDER BY available_copies;
    v_title  books.title%TYPE;
    v_copies books.available_copies%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_title, v_copies;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies left: % (% copies)', v_title, v_copies;
    END LOOP;
    CLOSE cur_low;
END $$;


DO $$
BEGIN
    CALL borrow_book(1, '202400104', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error caught: %', SQLERRM;
END $$;


SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
