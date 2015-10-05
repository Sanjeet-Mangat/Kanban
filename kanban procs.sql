USE Kanban;


DELIMITER ~
DROP PROCEDURE IF EXISTS simulate~
CREATE PROCEDURE simulate (IN hours float)
BEGIN  

	UPDATE worker w
	 SET timeRemaining = (SELECT workingTime FROM workerType  WHERE workerType.workerType = w.workerType)
	 WHERE 'm' = (SELECT task FROM workerType WHERE workerType.workerType = w.workerType);

	IF EXISTS (SELECT 1 FROM worker w WHERE w.workerType = (SELECT workerType FROM workerType WHERE task = 'r' LIMIT 0,1) LIMIT 0,1)
	THEN
		SET @i = 0;
		PREPARE stmt FROM
		  "UPDATE worker w
		  SET timeRemaining = ?
		  WHERE 'r' = (SELECT task FROM workerType WHERE wprkerType.workerType = w.workerType)
		  AND workerID IN
		  (SELECT DISTINCT workerID FROM worker JOIN workerType USING (workerID) WHERE task = 'r' ORDER BY workerID ASC LIMIT ?, 1);";

		WHILE (@i < (SELECT COUNT(DISTINCT workerID) FROM worker JOIN workerType USING (workerType)))
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
		UPDATE worker SET timeRemaining = timeRemaining - 1;
		SET @centiMinutesLeft = @centiMinutesLeft - 1;
	END WHILE;


END~
DELIMITER ;



CREATE OR REPLACE VIEW highDemandParts AS
  SELECT workerID, partName AS 'part', COUNT(DISTINCT timeRequested) AS 'total restock requests'
  FROM resupply JOIN part ON resupply.partID = part.partID
  GROUP BY workerID, resupply.partID ORDER BY COUNT(DISTINCT timeRequested);


DELIMITER ~
DROP TRIGGER IF EXISTS timeRemainingChanged~
CREATE TRIGGER timeRemainingChanged BEFORE UPDATE ON worker FOR EACH ROW
BEGIN

	IF NEW.timeRemaining = OLD.timeRemaining - 1
	THEN

		IF EXISTS (SELECT 1 FROM bin1 WHERE workerID = NEW.workerID AND quantity = 0 LIMIT 0,1)
		THEN
			SET NEW.timeRemaining = OLD.timeRemaining;

		ELSEIF NEW.timeRemaining = 0
		THEN
			SET NEW.timeRemaining = (SELECT workingTime FROM workerType WHERE NEW.workerType = workerType LIMIT 0,1);

			IF (SELECT task FROM workerType WHERE NEW.workerType = workerType LIMIT 0,1) = 'm'
			THEN
				CALL createAssembly(NEW.workerID);
			ELSE
				UPDATE resupply SET requestFilled = 1 WHERE TIME_TO_SEC(TIMEDIFF(CURRENT_TIMESTAMP, timeRequested)) >= 300 AND requestFilled = 0;
			END IF;
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
		SET @position =  (SELECT  MAX(CAST(SUBSTRING(testUnitNumber, 9, 2) AS UNSIGNED INTEGER)) FROM assembly) + 1;

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