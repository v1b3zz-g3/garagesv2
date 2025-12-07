-- qb-garages SQL Installation
-- Run this SQL file to set up all required database tables and fields

ALTER TABLE `player_vehicles` 
ADD COLUMN IF NOT EXISTS `is_favorite` INT DEFAULT 0,
ADD COLUMN IF NOT EXISTS `custom_name` VARCHAR(50) NULL,
ADD COLUMN IF NOT EXISTS `stored_in_gang` VARCHAR(50) NULL,
ADD COLUMN IF NOT EXISTS `shared_garage_id` INT NULL,
ADD COLUMN IF NOT EXISTS `impoundedtime` INT NULL,
ADD COLUMN IF NOT EXISTS `impoundreason` VARCHAR(255) NULL,
ADD COLUMN IF NOT EXISTS `impoundedby` VARCHAR(255) NULL,
ADD COLUMN IF NOT EXISTS `impoundtype` VARCHAR(50) NULL DEFAULT 'police',
ADD COLUMN IF NOT EXISTS `impoundfee` INT NULL,
ADD COLUMN IF NOT EXISTS `impoundtime` INT NULL;

-- Create gang_vehicles table
CREATE TABLE IF NOT EXISTS `gang_vehicles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `plate` varchar(15) NOT NULL,
  `gang` varchar(50) NOT NULL,
  `owner` varchar(50) NOT NULL,
  `vehicle` varchar(50) DEFAULT NULL,
  `stored` int(11) DEFAULT 1,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `plate` (`plate`),
  KEY `gang` (`gang`),
  KEY `owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Create shared_garages table
CREATE TABLE IF NOT EXISTS `shared_garages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL,
  `owner_citizenid` varchar(50) NOT NULL,
  `access_code` varchar(10) NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `owner_citizenid` (`owner_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Create shared_garage_members table
CREATE TABLE IF NOT EXISTS `shared_garage_members` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `garage_id` int(11) NOT NULL,
  `member_citizenid` varchar(50) NOT NULL,
  `joined_at` timestamp NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `garage_id` (`garage_id`),
  KEY `member_citizenid` (`member_citizenid`),
  CONSTRAINT `shared_garage_members_ibfk_1` FOREIGN KEY (`garage_id`) REFERENCES `shared_garages` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Create triggers to ensure data consistency
DELIMITER //
CREATE TRIGGER IF NOT EXISTS `update_gang_vehicle_stored_state` 
AFTER UPDATE ON `player_vehicles` 
FOR EACH ROW 
BEGIN
  IF NEW.state != OLD.state AND NEW.stored_in_gang IS NOT NULL THEN
    UPDATE `gang_vehicles` SET `stored` = NEW.state WHERE `plate` = NEW.plate;
  END IF;
END//
DELIMITER ;

-- Insert default values for testing (optional - comment out for production)
-- INSERT INTO `shared_garages` (`name`, `owner_citizenid`, `access_code`) VALUES
-- ('Test Garage', 'ABC123', '1234');