CREATE TABLE `branches` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`code` text NOT NULL,
	`active` integer DEFAULT 1 NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `branches_name_unique` ON `branches` (`name`);--> statement-breakpoint
CREATE UNIQUE INDEX `branches_code_unique` ON `branches` (`code`);
--> statement-breakpoint
INSERT INTO branches(id,name,code,active,created_at) VALUES
 ('aventura','Aventura','AV',0,strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 ('avenues','Avenues','AN',1,strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 ('dasma','Dasma','DA',1,strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 ('hessa','Hessa Al Mubarak','HM',1,strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 ('home','Home Service','HS',1,strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 ('mishref','Mishref','MI',1,strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 ('promenade','Promenade Mall','PM',1,strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 ('qurtoba','Qurtoba','QU',1,strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 ('yarmouk','Yarmouk','YA',1,strftime('%Y-%m-%dT%H:%M:%fZ','now')),
 ('zahra','Zahra Complex','ZC',1,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
--> statement-breakpoint
-- Preserve records belonging to any historical branch, even if it was not a default.
INSERT OR IGNORE INTO branches(id,name,code,active,created_at)
 SELECT branch,branch,'OLD-'||hex(branch),0,strftime('%Y-%m-%dT%H:%M:%fZ','now') FROM orders GROUP BY branch;
