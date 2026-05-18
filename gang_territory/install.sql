-- gang_territory schema
-- Import once before starting the resource.

CREATE TABLE IF NOT EXISTS `gt_gangs` (
    `job_name`    VARCHAR(50)  NOT NULL,
    `label`       VARCHAR(100) NOT NULL,
    `color_hex`   VARCHAR(7)   NOT NULL,
    `blip_color`  INT          NOT NULL DEFAULT 1,
    `hq_point_id` INT          NULL,
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`job_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gt_zones` (
    `id`    INT          NOT NULL AUTO_INCREMENT,
    `name`  VARCHAR(100) NOT NULL,
    `min_x` FLOAT        NOT NULL,
    `min_y` FLOAT        NOT NULL,
    `max_x` FLOAT        NOT NULL,
    `max_y` FLOAT        NOT NULL,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gt_spray_points` (
    `id`           INT         NOT NULL AUTO_INCREMENT,
    `pos_x`        FLOAT       NOT NULL,
    `pos_y`        FLOAT       NOT NULL,
    `pos_z`        FLOAT       NOT NULL,
    `heading`      FLOAT       NOT NULL DEFAULT 0,
    `owner_job`    VARCHAR(50) NULL,
    `locked_until` BIGINT      NULL,
    `zone_id`      INT         NULL,
    `created_at`   TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_owner` (`owner_job`),
    INDEX `idx_zone`  (`zone_id`),
    CONSTRAINT `fk_point_zone` FOREIGN KEY (`zone_id`)
        REFERENCES `gt_zones`(`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gt_neighbors` (
    `point_a_id` INT NOT NULL,
    `point_b_id` INT NOT NULL,
    PRIMARY KEY (`point_a_id`, `point_b_id`),
    CONSTRAINT `fk_neighbor_a` FOREIGN KEY (`point_a_id`)
        REFERENCES `gt_spray_points`(`id`) ON DELETE CASCADE,
    CONSTRAINT `fk_neighbor_b` FOREIGN KEY (`point_b_id`)
        REFERENCES `gt_spray_points`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gt_captures` (
    `id`                INT         NOT NULL AUTO_INCREMENT,
    `point_id`          INT         NOT NULL,
    `player_identifier` VARCHAR(60) NOT NULL,
    `from_job`          VARCHAR(50) NULL,
    `to_job`            VARCHAR(50) NOT NULL,
    `captured_at`       TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `week_number`       INT         NOT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_week`   (`week_number`),
    INDEX `idx_player` (`player_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `gt_weekly_winners` (
    `id`                INT         NOT NULL AUTO_INCREMENT,
    `week_number`       INT         NOT NULL,
    `job_name`          VARCHAR(50) NOT NULL,
    `point_count`       INT         NOT NULL,
    `mvp_identifier`    VARCHAR(60) NULL,
    `mvp_capture_count` INT         NOT NULL DEFAULT 0,
    `awarded_at`        TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_week_job` (`week_number`, `job_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed example gangs (edit / remove as needed)
INSERT INTO `gt_gangs` (`job_name`, `label`, `color_hex`, `blip_color`) VALUES
    ('ballas',   'The Ballas',   '#A020F0', 27),
    ('families', 'The Families', '#2ECC71', 25),
    ('vagos',    'Los Vagos',    '#F1C40F', 5)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);
