USE flightradar_db;

-- 1. Додаткова таблиця 1:M без фізичного Foreign Key + 3 тригери цілісності

CREATE TABLE IF NOT EXISTS maintenance_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    aircraft_id INT NOT NULL,
    description VARCHAR(255) NOT NULL,
    maintenance_date DATE NOT NULL
) ENGINE=InnoDB;

DROP TRIGGER IF EXISTS trg_maintenance_log_before_insert;
DROP TRIGGER IF EXISTS trg_maintenance_log_before_update;
DROP TRIGGER IF EXISTS trg_aircraft_before_delete_maintenance;

DELIMITER //

CREATE TRIGGER trg_maintenance_log_before_insert
BEFORE INSERT ON maintenance_log
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM aircraft WHERE id = NEW.aircraft_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Integrity error: aircraft_id does not exist in aircraft table';
    END IF;
END //

CREATE TRIGGER trg_maintenance_log_before_update
BEFORE UPDATE ON maintenance_log
FOR EACH ROW
BEGIN
    IF NOT EXISTS (SELECT 1 FROM aircraft WHERE id = NEW.aircraft_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Integrity error: aircraft_id does not exist in aircraft table';
    END IF;
END //

CREATE TRIGGER trg_aircraft_before_delete_maintenance
BEFORE DELETE ON aircraft
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM maintenance_log WHERE aircraft_id = OLD.id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Integrity error: cannot delete aircraft with existing maintenance_log records';
    END IF;
END //

DELIMITER ;

-- 2. Збережені процедури та користувацька функція

DROP PROCEDURE IF EXISTS sp_insert_flight_route;
DROP PROCEDURE IF EXISTS sp_assign_crew_member;
DROP PROCEDURE IF EXISTS sp_insert_ten_noname_countries;
DROP FUNCTION IF EXISTS fn_get_max_aircraft_flights;
DROP PROCEDURE IF EXISTS sp_show_max_aircraft_flights;
DROP PROCEDURE IF EXISTS sp_split_country_randomly;

DELIMITER //

-- 2a. Параметризована вставка у flight_route з поверненням LAST_INSERT_ID()
CREATE PROCEDURE sp_insert_flight_route(
    IN p_distance_km INT,
    IN p_route_description VARCHAR(100)
)
BEGIN
    INSERT INTO flight_route (distance_km, route_description)
    VALUES (p_distance_km, p_route_description);

    SELECT LAST_INSERT_ID() AS id,
           p_distance_km AS distance_km,
           p_route_description AS route_description;
END //

-- 2b. Реалізація зв'язку M:M у таблиці crew за реальними значеннями
CREATE PROCEDURE sp_assign_crew_member(
    IN p_person_name VARCHAR(50),
    IN p_person_surname VARCHAR(50),
    IN p_aircraft_name VARCHAR(50)
)
BEGIN
    DECLARE v_person_id INT DEFAULT NULL;
    DECLARE v_aircraft_id INT DEFAULT NULL;

    SELECT id INTO v_person_id
    FROM person
    WHERE name = p_person_name AND surname = p_person_surname
    LIMIT 1;

    IF v_person_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Person not found';
    END IF;

    SELECT id INTO v_aircraft_id
    FROM aircraft
    WHERE name = p_aircraft_name
    LIMIT 1;

    IF v_aircraft_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Aircraft not found';
    END IF;

    INSERT INTO crew (person_id, aircraft_id)
    VALUES (v_person_id, v_aircraft_id);

    SELECT v_person_id AS person_id,
           v_aircraft_id AS aircraft_id,
           CONCAT(p_person_name, ' ', p_person_surname) AS person_name,
           p_aircraft_name AS aircraft_name;
END //

-- 2c. Пакетна вставка 10 стрічок Noname1..Noname10 у таблицю country
CREATE PROCEDURE sp_insert_ten_noname_countries()
BEGIN
    DECLARE v_i INT DEFAULT 1;

    WHILE v_i <= 10 DO
        INSERT INTO country (name) VALUES (CONCAT('Noname', v_i));
        SET v_i = v_i + 1;
    END WHILE;

    SELECT 10 AS inserted_count;
END //

-- 2d. Користувацька функція для MAX(total_flight) + процедура, що її викликає
CREATE FUNCTION fn_get_max_aircraft_flights()
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_max INT DEFAULT 0;
    SELECT COALESCE(MAX(total_flight), 0) INTO v_max FROM aircraft;
    RETURN v_max;
END //

CREATE PROCEDURE sp_show_max_aircraft_flights()
BEGIN
    SELECT fn_get_max_aircraft_flights() AS max_total_flight;
END //

-- 2e. Процедура з курсором для випадкового розбиття country на 2 таблиці зі штампом часу
CREATE PROCEDURE sp_split_country_randomly()
BEGIN
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_id INT;
    DECLARE v_name VARCHAR(50);
    DECLARE v_ts VARCHAR(32);
    DECLARE v_table1 VARCHAR(64);
    DECLARE v_table2 VARCHAR(64);

    DECLARE cur_country CURSOR FOR SELECT id, name FROM country;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    SET v_ts = DATE_FORMAT(NOW(), '%Y%m%d_%H%i%s');
    SET v_table1 = CONCAT('country_part1_', v_ts);
    SET v_table2 = CONCAT('country_part2_', v_ts);

    SET @sql_create1 = CONCAT('CREATE TABLE IF NOT EXISTS `', v_table1, '` LIKE country');
    PREPARE stmt1 FROM @sql_create1;
    EXECUTE stmt1;
    DEALLOCATE PREPARE stmt1;

    SET @sql_create2 = CONCAT('CREATE TABLE IF NOT EXISTS `', v_table2, '` LIKE country');
    PREPARE stmt2 FROM @sql_create2;
    EXECUTE stmt2;
    DEALLOCATE PREPARE stmt2;

    SET @sql_ins1 = CONCAT('INSERT INTO `', v_table1, '` (id, name) VALUES (?, ?)');
    PREPARE stmt_ins1 FROM @sql_ins1;

    SET @sql_ins2 = CONCAT('INSERT INTO `', v_table2, '` (id, name) VALUES (?, ?)');
    PREPARE stmt_ins2 FROM @sql_ins2;

    OPEN cur_country;

    read_loop: LOOP
        FETCH cur_country INTO v_id, v_name;
        IF v_done = 1 THEN
            LEAVE read_loop;
        END IF;

        SET @c_id = v_id;
        SET @c_name = v_name;

        IF RAND() < 0.5 THEN
            EXECUTE stmt_ins1 USING @c_id, @c_name;
        ELSE
            EXECUTE stmt_ins2 USING @c_id, @c_name;
        END IF;
    END LOOP;

    CLOSE cur_country;

    DEALLOCATE PREPARE stmt_ins1;
    DEALLOCATE PREPARE stmt_ins2;

    SELECT v_table1 AS table1, v_table2 AS table2;
END //

DELIMITER ;

-- 3. Три  тригери

CREATE TABLE IF NOT EXISTS flight_delete_log (
    log_id INT AUTO_INCREMENT PRIMARY KEY,
    deleted_flight_id INT NOT NULL,
    aircraft_id INT NOT NULL,
    status VARCHAR(50) NOT NULL,
    deleted_at DATETIME NOT NULL
) ENGINE=InnoDB;

DROP TRIGGER IF EXISTS trg_registration_info_before_insert;
DROP TRIGGER IF EXISTS trg_role_before_delete;
DROP TRIGGER IF EXISTS trg_flight_after_delete;

DELIMITER //

-- 3a. Заборонити serial_number, що закінчується на 00
CREATE TRIGGER trg_registration_info_before_insert
BEFORE INSERT ON registration_info
FOR EACH ROW
BEGIN
    IF NEW.serial_number % 100 = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Business rule error: serial_number cannot end with 00';
    END IF;
END //

-- 3b. Заборонити видалення стрічок з role
CREATE TRIGGER trg_role_before_delete
BEFORE DELETE ON role
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Deleting rows from role table is forbidden';
END //

-- 3c. Логування видалення з flight у flight_delete_log
CREATE TRIGGER trg_flight_after_delete
AFTER DELETE ON flight
FOR EACH ROW
BEGIN
    INSERT INTO flight_delete_log (deleted_flight_id, aircraft_id, status, deleted_at)
    VALUES (OLD.id, OLD.aircraft_id, OLD.status, NOW());
END //

DELIMITER ;


-- Наповнення таблиці maintenance_log тестовими записами

INSERT INTO maintenance_log (aircraft_id, description, maintenance_date) VALUES
    (1, 'Scheduled A-Check and engine inspection', '2026-08-10'),
    (1, 'Landing gear hydraulic fluid replacement', '2026-10-15'),
    (2, 'Avionics software update and radar calibration', '2026-09-01'),
    (3, 'Cabin pressure valve replacement', '2026-07-25'),
    (4, 'Routine wing flap and actuator check', '2026-08-30'),
    (5, 'Full C-Check structural inspection', '2026-09-15');
