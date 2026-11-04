CREATE TABLE `job_events` (
	`id` text PRIMARY KEY NOT NULL,
	`order_id` text NOT NULL,
	`branch` text NOT NULL,
	`actor` text NOT NULL,
	`actor_name` text NOT NULL,
	`action` text NOT NULL,
	`detail` text NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`order_id`) REFERENCES `orders`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
ALTER TABLE `orders` ADD `tailor_id` text REFERENCES members(id);--> statement-breakpoint
ALTER TABLE `orders` ADD `job_status` text DEFAULT 'Pending' NOT NULL;--> statement-breakpoint
ALTER TABLE `orders` ADD `assigned_at` text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE `orders` ADD `job_updated_at` text DEFAULT '' NOT NULL;