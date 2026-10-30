CREATE TABLE `attachments` (
	`id` text PRIMARY KEY NOT NULL,
	`branch` text NOT NULL,
	`order_id` text,
	`name` text NOT NULL,
	`type` text NOT NULL,
	`object_key` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `audit` (
	`id` text PRIMARY KEY NOT NULL,
	`branch` text NOT NULL,
	`actor` text NOT NULL,
	`action` text NOT NULL,
	`entity` text NOT NULL,
	`detail` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `customers` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`phone` text NOT NULL,
	`address` text DEFAULT '' NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `expenses` (
	`id` text PRIMARY KEY NOT NULL,
	`branch` text NOT NULL,
	`category` text NOT NULL,
	`description` text NOT NULL,
	`amount` integer NOT NULL,
	`method` text NOT NULL,
	`actor` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `members` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text,
	`email` text NOT NULL,
	`name` text NOT NULL,
	`role` text NOT NULL,
	`branches` text NOT NULL,
	`active` integer DEFAULT 1 NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `members_user_id_unique` ON `members` (`user_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `members_email_unique` ON `members` (`email`);--> statement-breakpoint
CREATE TABLE `orders` (
	`id` text PRIMARY KEY NOT NULL,
	`branch` text NOT NULL,
	`bill` text NOT NULL,
	`kind` text NOT NULL,
	`customer_id` text,
	`customer_name` text NOT NULL,
	`phone` text DEFAULT '' NOT NULL,
	`address` text DEFAULT '' NOT NULL,
	`lines` text NOT NULL,
	`subtotal` integer NOT NULL,
	`discount` integer NOT NULL,
	`extra` integer NOT NULL,
	`total` integer NOT NULL,
	`paid` integer DEFAULT 0 NOT NULL,
	`notes` text DEFAULT '' NOT NULL,
	`cashier` text NOT NULL,
	`cashier_id` text NOT NULL,
	`staff` text DEFAULT '' NOT NULL,
	`aggregator` text DEFAULT '' NOT NULL,
	`status` text DEFAULT 'Ongoing' NOT NULL,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	`due_date` text DEFAULT '' NOT NULL,
	`version` integer DEFAULT 0 NOT NULL,
	`booking_id` text,
	`external_id` text
);
--> statement-breakpoint
CREATE UNIQUE INDEX `orders_bill_unique` ON `orders` (`bill`);--> statement-breakpoint
CREATE UNIQUE INDEX `orders_external_id_unique` ON `orders` (`external_id`);--> statement-breakpoint
CREATE TABLE `payments` (
	`id` text PRIMARY KEY NOT NULL,
	`order_id` text NOT NULL,
	`branch` text NOT NULL,
	`amount` integer NOT NULL,
	`method` text NOT NULL,
	`reference` text DEFAULT '' NOT NULL,
	`actor` text NOT NULL,
	`created_at` text NOT NULL,
	FOREIGN KEY (`order_id`) REFERENCES `orders`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `prices` (
	`id` text PRIMARY KEY NOT NULL,
	`price` integer NOT NULL,
	`active` integer DEFAULT 1 NOT NULL
);
