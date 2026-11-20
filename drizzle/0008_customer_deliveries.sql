CREATE TABLE `customer_deliveries` (
	`id` text PRIMARY KEY NOT NULL,
	`order_id` text NOT NULL,
	`branch` text NOT NULL,
	`payload` text NOT NULL,
	`desired_status` text DEFAULT 'new' NOT NULL,
	`revision` integer DEFAULT 0 NOT NULL,
	`remote_id` text DEFAULT '' NOT NULL,
	`remote_status` text DEFAULT '' NOT NULL,
	`sync_state` text DEFAULT 'pending' NOT NULL,
	`attempts` integer DEFAULT 0 NOT NULL,
	`next_attempt` text DEFAULT '' NOT NULL,
	`last_error` text DEFAULT '' NOT NULL,
	`driver_name` text DEFAULT '' NOT NULL,
	`eta_label` text DEFAULT '' NOT NULL,
	`eta_at` text DEFAULT '' NOT NULL,
	`delivered_at` text DEFAULT '' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	`created_by` text NOT NULL,
	FOREIGN KEY (`order_id`) REFERENCES `orders`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`branch`) REFERENCES `branches`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `customer_deliveries_order_id_unique` ON `customer_deliveries` (`order_id`);--> statement-breakpoint
CREATE TABLE `inventory_branch_mappings` (
	`branch` text PRIMARY KEY NOT NULL,
	`inventory_branch_id` text NOT NULL,
	`updated_at` text NOT NULL,
	`updated_by` text NOT NULL,
	FOREIGN KEY (`branch`) REFERENCES `branches`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `inventory_branch_mappings_inventory_branch_id_unique` ON `inventory_branch_mappings` (`inventory_branch_id`);