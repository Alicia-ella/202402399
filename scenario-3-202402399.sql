DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;
DROP PROCEDURE IF EXISTS reserve_workstations(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS cancel_reservation(INT);

CREATE TABLE lab_sessions (
    session_id             SERIAL PRIMARY KEY,
    session_name           VARCHAR(100) NOT NULL,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    session_id     INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer       VARCHAR(100) NOT NULL,
    workstations   INT NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'RESERVED'
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 - Lab A', 30),
    ('Tuesday 10:00 - Lab B', 4),
    ('Wednesday 14:00 - Lab C', 0);

SELECT * FROM lab_sessions ORDER BY session_id;


DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '%: FULL', rec.session_name;
        ELSIF rec.available_workstations <= 5 THEN
            RAISE NOTICE '%: NEARLY FULL (% left)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '%: enough workstations (%)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $

DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', n;
        n := n + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Workstation check %', chk;
    END LOOP;
END $$;



CREATE OR REPLACE PROCEDURE reserve_workstations(p_session_id INT, p_lecturer VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_avail INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_qty;
    END IF;

    SELECT available_workstations INTO v_avail
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF v_avail < p_qty THEN
        RAISE NOTICE 'Reservation rejected for %: requested %, only % available',
                     p_lecturer, p_qty, v_avail;
        RETURN;
    END IF;

    UPDATE lab_sessions SET available_workstations = available_workstations - p_qty
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations, status)
    VALUES (p_session_id, p_lecturer, p_qty, 'RESERVED');

    RAISE NOTICE 'Reservation recorded: % reserved % workstation(s) in session %',
                 p_lecturer, p_qty, p_session_id;
END $$;


CALL reserve_workstations(1, 'Dr. Banda', 20);    -- valid
CALL reserve_workstations(2, 'Mr. Phiri', 3);     -- valid
CALL reserve_workstations(2, 'Ms. Mwansa', 10);   -- exceeds capacity (only 1 left)

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;


CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status     VARCHAR(20);
    v_qty        INT;
    v_session_id INT;
BEGIN
    SELECT status, workstations, session_id
    INTO v_status, v_qty, v_session_id
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Reservation % does not exist', p_reservation_id;
        RETURN;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled, nothing released', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions SET available_workstations = available_workstations + v_qty
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled, % workstation(s) released', p_reservation_id, v_qty;
END $$;

CALL cancel_reservation(2);   -- first call: releases workstations
CALL cancel_reservation(2);   -- second call: nothing released

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;


DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_name, available_workstations FROM lab_sessions
        WHERE available_workstations <= 5 ORDER BY available_workstations;
    v_name  lab_sessions.session_name%TYPE;
    v_avail lab_sessions.available_workstations%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_name, v_avail;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations left: % (%)', v_name, v_avail;
    END LOOP;
    CLOSE cur_low;
END $$;

DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Banda', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error caught: %', SQLERRM;
END $$;


SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
