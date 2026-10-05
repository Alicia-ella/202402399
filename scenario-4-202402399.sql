DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;
DROP PROCEDURE IF EXISTS dispense_medicine(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS reverse_dispensing(INT);


CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'DISPENSED'
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol', 100),
    ('Amoxicillin', 8),
    ('Cetirizine', 0);

SELECT * FROM medicines ORDER BY medicine_id;


DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '%: OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity <= 10 THEN
            RAISE NOTICE '%: LOW stock (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '%: sufficiently stocked (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;


DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Stock review day %', n;
        n := n + 1;
    END LOOP;

    FOR insp IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection %', insp;
    END LOOP;
END $$;


CREATE OR REPLACE PROCEDURE dispense_medicine(p_medicine_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_qty;
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF v_stock < p_qty THEN
        RAISE NOTICE 'Dispensing rejected for student %: requested %, only % in stock',
                     p_student, p_qty, v_stock;
        RETURN;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_qty
    WHERE medicine_id = p_medicine_id;

    INSERT INTO dispensing_records (medicine_id, student_number, quantity, status)
    VALUES (p_medicine_id, p_student, p_qty, 'DISPENSED');

    RAISE NOTICE 'Dispensed % unit(s) of medicine % to student %',
                 p_qty, p_medicine_id, p_student;
END $$;



CALL dispense_medicine(1, '202400301', 20);   -- valid
CALL dispense_medicine(2, '202400302', 3);    -- valid
CALL dispense_medicine(2, '202400303', 20);   -- exceeds stock (rejected)

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;


CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status      VARCHAR(20);
    v_qty         INT;
    v_medicine_id INT;
BEGIN
    SELECT status, quantity, medicine_id
    INTO v_status, v_qty, v_medicine_id
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Dispensing record % does not exist', p_record_id;
        RETURN;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % was already reversed, stock not restored again', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_qty
    WHERE medicine_id = v_medicine_id;

    RAISE NOTICE 'Record % reversed, % unit(s) restored to stock', p_record_id, v_qty;
END $$;

CALL reverse_dispensing(2);   -- first call: restores stock
CALL reverse_dispensing(2);   -- second call: nothing restored

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;


DO $$
DECLARE
    c_threshold CONSTANT INT := 10;
    cur_low CURSOR (p_limit INT) FOR
        SELECT medicine_name, stock_quantity FROM medicines
        WHERE stock_quantity < p_limit ORDER BY stock_quantity;
    v_name  medicines.medicine_name%TYPE;
    v_stock medicines.stock_quantity%TYPE;
BEGIN
    OPEN cur_low(c_threshold);
    LOOP
        FETCH cur_low INTO v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold of %: % (% in stock)', c_threshold, v_name, v_stock;
    END LOOP;
    CLOSE cur_low;
END $$;


DO $$
BEGIN
    CALL dispense_medicine(1, '202400304', -5);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error caught: %', SQLERRM;
END $$;


SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
