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
	timeWastedWaitingForPart int DEFAULT 0,
    PRIMARY KEY (partID)
);

CREATE TABLE bin1 (
    partID int NOT NULL,
    workerID int NOT NULL,
    quantity int,
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
    requestFilled bit DEFAULT 0,
    PRIMARY KEY (partID , workerID , timeRequested),
    FOREIGN KEY (partID , workerID)
        REFERENCES bin1 (partID , workerID)
);



INSERT INTO workerType (workingTime, task) values (100, 'm'), (150, 'm'), (85, 'm'), (500, 'r');