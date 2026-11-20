ALTER TABLE `customer_deliveries` ADD `delivery_invoice_id` text REFERENCES orders(id);--> statement-breakpoint
ALTER TABLE `customer_deliveries` ADD `approved_at` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `customer_deliveries` ADD `approved_by` text;--> statement-breakpoint
ALTER TABLE `orders` ADD `charge_kind` text DEFAULT '' NOT NULL;
--> statement-breakpoint
INSERT OR IGNORE INTO branches(id,name,code,active,created_at)
VALUES ('aventura','Aventura','AV',1,strftime('%Y-%m-%dT%H:%M:%fZ','now'));
UPDATE branches SET active=1 WHERE id='aventura';
-- Preserve existing sent deliveries, but hold every unsent request for explicit
-- Reception approval. No new inventory request is created by this migration.
UPDATE customer_deliveries SET desired_status='draft',sync_state='draft',approved_at='',approved_by=NULL
WHERE remote_id='' AND desired_status<>'cancelled';
