-- Project-owned cloud saves for signed-in Manus players.
CREATE TABLE IF NOT EXISTS game_cloud_saves (
  user_id INT NOT NULL,
  slot VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  label VARCHAR(80) NOT NULL,
  day INT UNSIGNED NOT NULL DEFAULT 0,
  population INT UNSIGNED NOT NULL DEFAULT 0,
  mood INT UNSIGNED NOT NULL DEFAULT 0,
  payload LONGTEXT NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY(user_id, slot),
  KEY updated(updated_at)
);

-- Casual, client-reported rankings. Board IDs and rules are immutable.
INSERT IGNORE INTO game_lb_boards
(namespace,id,rules_version,direction,min_score,max_score,min_duration_ms,max_duration_ms,`open`)
VALUES
('production','survival-days-v1','v1','desc',0,36500,60000,1800000,TRUE),
('production','population-v1','v1','desc',0,1000,60000,1800000,TRUE),
('production','mood-v1','v1','desc',0,10000,60000,1800000,TRUE);
