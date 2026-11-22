-- Keep the original branch ID and invoice code so historical records and staff
-- assignments continue to belong to Home Service on existing installations.
INSERT OR IGNORE INTO branches(id,name,code,active,created_at)
VALUES ('home','Home Service','HS',1,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
--> statement-breakpoint
UPDATE branches SET active=1 WHERE id='home';
