DROP DATABASE IF EXISTS kanban;

CREATE DATABASE kanban;

USE kanban;

CREATE TABLE workerType (
    workerType int NOT NULL AUTO_INCREMENT,
    workingTime int,
	task char,
    PRIMARY KEY (workerType)
);

CREATE TABLE worker (
    workerID int NOT null AUTO_INCREMENT,
    workerType int NOT NULL,
	timeRemaining int,
    PRIMARY KEY (workerID),
    FOREIGN KEY (workerType)
        REFERENCES workerType (workerType)
);

CREATE TABLE assembly (
    testUnitNumber char(10) NOT NULL,
    workerID int NOT NULL,
    PRIMARY KEY (testUnitNumber),
    FOREIGN KEY (workerID)
        REFERENCES worker (workerID)
);

CREATE TABLE part (
    partName varchar(10),
    partID int NOT NULL AUTO_INCREMENT,
    partsPerBin int,
    PRIMARY KEY (partID)
);

CREATE TABLE bin1 (
    partID int NOT NULL,
    workerID int NOT NULL,
    quantity int,
	timeWastedWaitingForPart int DEFAULT 0,
    PRIMARY KEY (partID , workerID),
    FOREIGN KEY (partID)
        REFERENCES part (partID),
    FOREIGN KEY (workerID)
        REFERENCES worker (workerID)
);

CREATE TABLE resupply (
    partID int NOT NULL,
    workerID int NOT NULL,
    timeRequested timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    timeSinceRequested int DEFAULT 0,
    requestFilled bit DEFAULT 0,
    PRIMARY KEY (partID , workerID , timeRequested),
    FOREIGN KEY (partID , workerID)
        REFERENCES bin1 (partID , workerID)
);


DELIMITER ~
DROP PROCEDURE IF EXISTS simulate~
CREATE PROCEDURE simulate (IN hours float)
BEGIN  

	UPDATE worker JOIN workertype USING (workerType) SET timeRemaining = workingTime WHERE task = 'm';

	IF EXISTS (SELECT 1 FROM worker w WHERE w.workerType = (SELECT workerType FROM workerType WHERE task = 'r' LIMIT 0,1) LIMIT 0,1)
	THEN
		SET @i = 0;
		PREPARE stmt FROM
		  "UPDATE worker JOIN workerType using (workerType) SET timeRemaining = ? WHERE task = 'r'
		  AND workerID = (SELECT workerID FROM (SELECT DISTINCT workerID FROM worker JOIN workerType USING (workerType) WHERE task = 'r' ORDER BY workerID ASC LIMIT ?, 1) AS x);";

		WHILE (@i < (SELECT COUNT(DISTINCT workerID) FROM worker JOIN workerType USING (workerType) WHERE task = 'r'))
		DO
			SET @j = (SELECT workingTime FROM workerType WHERE task = 'r' LIMIT 0,1) / (@i + 1);
			EXECUTE stmt USING @j, @i;
			SET @i = @i + 1;
		END WHILE;

		DEALLOCATE PREPARE stmt;
	END IF;

	SET @centiMinutesLeft = hours * 6000;
	WHILE (@centiMinutesLeft > 0)
	DO
		SET @decrementAmount = (SELECT MIN(timeRemaining) FROM worker);
		UPDATE resupply SET timeSinceRequested = timeSinceRequested + @decrementAmount WHERE requestFilled = 0;
		UPDATE worker SET timeRemaining = timeRemaining - @decrementAmount;
		SET @centiMinutesLeft = @centiMinutesLeft - @decrementAmount;
	END WHILE;


END~
DELIMITER ;



CREATE OR REPLACE VIEW highDemandParts AS
  SELECT workerID, partName AS 'part', COUNT( timeRequested) AS 'total restock requests', timeWastedWaitingForPart / 100 AS  'Minutes wasted waiting on more parts'
  FROM resupply JOIN bin1 USING (partID, workerID) JOIN part ON resupply.partID = part.partID
  GROUP BY workerID, resupply.partID ORDER BY timeWastedWaitingForPart DESC, COUNT(timeRequested) DESC, workerID;


DELIMITER ~
DROP TRIGGER IF EXISTS timeRemainingChanged~
CREATE TRIGGER timeRemainingChanged BEFORE UPDATE ON worker FOR EACH ROW
BEGIN

	IF EXISTS (SELECT 1 FROM bin1 WHERE workerID = NEW.workerID AND quantity = 0 LIMIT 0,1)
	THEN
		SET NEW.timeRemaining = OLD.timeRemaining;
		UPDATE bin1 SET timeWastedWaitingForPart = timeWastedWaitingForPart + 1 WHERE workerID = NEW.workerID AND quantity = 0;

	ELSEIF NEW.timeRemaining = 0
	THEN
		SET NEW.timeRemaining = (SELECT workingTime FROM workerType WHERE NEW.workerType = workerType LIMIT 0,1);

		IF (SELECT task FROM workerType WHERE NEW.workerType = workerType LIMIT 0,1) = 'm'
		THEN
			CALL createAssembly(NEW.workerID);
		ELSE
			UPDATE resupply SET requestFilled = 1 WHERE timeSinceRequested >= (SELECT workingTime FROM workerType WHERE NEW.workerType = workerType LIMIT 0,1) AND requestFilled = 0;
		END IF;
	END IF;
END~
DELIMITER ; 



DELIMITER ~
DROP TRIGGER IF EXISTS resupplyFilled~
CREATE TRIGGER resupplyFilled AFTER UPDATE ON resupply FOR EACH ROW
BEGIN
	IF NEW.requestFilled = 1 AND OLD.requestFilled = 0
	THEN
		UPDATE bin1 b SET quantity = quantity + (SELECT partsPerBin FROM part WHERE partID = b.partID LIMIT 0,1) WHERE partID = NEW.partID AND workerID = NEW.workerID;
	END IF;
END~
DELIMITER ;


DELIMITER ~
DROP TRIGGER IF EXISTS requestResupply~
CREATE TRIGGER requestResupply AFTER UPDATE ON bin1 FOR EACH ROW
BEGIN
	IF NEW.quantity = 5
	THEN
		INSERT INTO resupply (partID, workerID) VALUES (NEW.partID, NEW.workerID);
	END IF;
END~
DELIMITER ;



DELIMITER ~
DROP PROCEDURE IF EXISTS createAssembly~
CREATE PROCEDURE createAssembly (IN workerID int)
BEGIN
	UPDATE bin1 b SET quantity = quantity-1 WHERE b.workerID = workerID;

	IF EXISTS (SELECT 1 FROM assembly LIMIT 0,1)
	THEN
		SET @trayNum = (SELECT  MAX(CAST(SUBSTRING(testUnitNumber, 3, 6) AS UNSIGNED INTEGER)) FROM assembly);
		SET @position =  (SELECT MAX(CAST(SUBSTRING(testUnitNumber, 3, 8) AS UNSIGNED INTEGER)) FROM assembly) % 100 + 1;

		IF @position = 60
		THEN
			SET @position = 0;
			SET @trayNum = @trayNum + 1;
		END IF;

	ELSE
		SET @trayNum = 0;
		SET @position = 0;
	END IF;

	INSERT INTO assembly(testUnitNumber, workerID) values (CONCAT("FL", LPAD(@trayNum, 6, '0'), LPAD(@position, 2, '0')), workerID);
END~
DELIMITER ;


INSERT INTO workerType (workingTime, task) values (100, 'm'), (150, 'm'), (85, 'm'), (500, 'r');

INSERT INTO part (partName, partsPerBin) VALUES ("Harness", 75), ("Reflector", 35), ("Housing", 25), ("Lens", 40), ("Bulb", 50), ("Bezel", 75);

INSERT INTO worker (workertype) values (1), (1), (1), (4);

INSERT INTO bin1 (partID, workerID, Quantity) SELECT partID, workerID, partsPerBin FROM worker w CROSS JOIN part WHERE workerType IN (SELECT workerType FROM workerType WHERE task = 'm');

CALL simulate (7);

SELECT * FROM highDemandParts;