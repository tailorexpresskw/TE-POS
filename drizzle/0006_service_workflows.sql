CREATE TABLE `integration_events` (
	`id` text PRIMARY KEY NOT NULL,
	`order_id` text NOT NULL,
	`branch` text NOT NULL,
	`type` text NOT NULL,
	`payload` text NOT NULL,
	`created_at` text NOT NULL,
	`processed_at` text DEFAULT '' NOT NULL,
	FOREIGN KEY (`order_id`) REFERENCES `orders`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `work_credits` (
	`id` text PRIMARY KEY NOT NULL,
	`task_id` text NOT NULL,
	`order_id` text NOT NULL,
	`line_index` integer NOT NULL,
	`tailor_id` text NOT NULL,
	`quantity` integer NOT NULL,
	`amount` integer NOT NULL,
	`reason` text NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`task_id`) REFERENCES `work_items`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`order_id`) REFERENCES `orders`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`tailor_id`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `work_items` (
	`id` text PRIMARY KEY NOT NULL,
	`order_id` text NOT NULL,
	`line_index` integer NOT NULL,
	`quantity` integer NOT NULL,
	`tailor_id` text,
	`status` text DEFAULT 'Pending' NOT NULL,
	`kind` text DEFAULT 'original' NOT NULL,
	`parent_task_id` text,
	`fault` text DEFAULT '' NOT NULL,
	`fault_tailor_id` text,
	`reason` text DEFAULT '' NOT NULL,
	`approved_by` text,
	`approved_at` text DEFAULT '' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	`version` integer DEFAULT 0 NOT NULL,
	FOREIGN KEY (`order_id`) REFERENCES `orders`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`tailor_id`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
ALTER TABLE `members` ADD `permissions` text DEFAULT '{}' NOT NULL;--> statement-breakpoint
ALTER TABLE `notifications` ADD `task_id` text;--> statement-breakpoint
ALTER TABLE `orders` ADD `parent_order_id` text;--> statement-breakpoint
ALTER TABLE `orders` ADD `document_type` text DEFAULT 'invoice' NOT NULL;--> statement-breakpoint
ALTER TABLE `orders` ADD `refunded_total` integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE `orders` ADD `reason` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `orders` ADD `reason_code` text DEFAULT '' NOT NULL;
--> statement-breakpoint
CREATE INDEX work_items_order ON work_items(order_id,line_index);
CREATE INDEX work_items_tailor_status ON work_items(tailor_id,status);
CREATE INDEX work_credits_order_tailor ON work_credits(order_id,tailor_id,line_index);
CREATE INDEX orders_parent ON orders(parent_order_id);
CREATE INDEX integration_events_pending ON integration_events(processed_at,created_at);
--> statement-breakpoint
INSERT INTO work_items(id,order_id,line_index,quantity,tailor_id,status,kind,reason,approved_at,created_at,updated_at)
 SELECT o.id||':line:'||j.key,o.id,CAST(j.key AS INTEGER),json_extract(j.value,'$.qty'),o.tailor_id,
 CASE WHEN o.status IN ('Voided','Refunded') THEN 'Cancelled' ELSE o.job_status END,'original',
 CASE WHEN o.job_status='Completed' THEN 'Migrated completed work' ELSE '' END,
 CASE WHEN o.job_status='Completed' THEN o.updated_at ELSE '' END,o.created_at,o.updated_at
 FROM orders o,json_each(o.lines) j WHERE o.kind='sale' AND json_extract(j.value,'$.qty')>0;
--> statement-breakpoint
WITH raw AS (
 SELECT w.id task_id,w.order_id,w.line_index,w.quantity,w.tailor_id,w.approved_at,
 json_extract(j.value,'$.qty')*json_extract(j.value,'$.price') gross,o.subtotal,o.subtotal-o.discount net
 FROM work_items w JOIN orders o ON o.id=w.order_id JOIN json_each(o.lines) j ON CAST(j.key AS INTEGER)=w.line_index
), allocated AS (
 SELECT *,COALESCE(CAST(gross*net/NULLIF(subtotal,0) AS INTEGER),0) base,
 ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY COALESCE((gross*net)%NULLIF(subtotal,0),0) DESC,line_index) rank,
 SUM(COALESCE(CAST(gross*net/NULLIF(subtotal,0) AS INTEGER),0)) OVER(PARTITION BY order_id) base_sum FROM raw
)
INSERT INTO work_credits(id,task_id,order_id,line_index,tailor_id,quantity,amount,reason,created_at)
 SELECT 'legacy:'||a.task_id,a.task_id,a.order_id,a.line_index,a.tailor_id,a.quantity,
 a.base+CASE WHEN a.rank<=a.net-a.base_sum THEN 1 ELSE 0 END,'legacy_approved',a.approved_at
 FROM allocated a JOIN work_items w ON w.id=a.task_id WHERE w.status='Completed' AND a.tailor_id IS NOT NULL;
